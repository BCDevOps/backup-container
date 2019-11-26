  #!/bin/bash

# =================================================================================================================
# Usage:
# -----------------------------------------------------------------------------------------------------------------
function usage () {
  cat <<-EOF

  Automated backup script for Postgresql and MongoDB databases.

  There are two modes of scheduling backups:
    - Cron Mode:
      - Allows one or more schedules to be defined as cron tabs in ${BACKUP_CONF}.
      - If cron (go-crond) is installed (which is handled by the Docker file) and at least one cron tab is defined, the script will startup in Cron Mode,
        otherwise it will default to Legacy Mode.
      - Refer to ${BACKUP_CONF} for additional details and examples of using cron scheduling.

    - Legacy Mode:
      - Uses a simple sleep command to set the schedule based on the setting of BACKUP_PERIOD; defaults to ${BACKUP_PERIOD}

  Refer to the project documentation for additional details on how to use this script.
  - https://github.com/BCDevOps/backup-container

  Usage:
    $0 [options]

  Standard Options:
  =================
    -h prints this usage documentation.

    -1 run once.
       Performs a single set of backups and exits.

    -s run in scheduled/silent (no questions asked) mode.
       A flag to be used by cron scheduled backups to indicate they are being run on a schedule.
       Requires cron (go-crond) to be installed and at least one cron tab to be defined in ${BACKUP_CONF}
       Refer to ${BACKUP_CONF} for additional details and examples of using cron scheduling.

    -l lists existing backups.
       Great for listing the available backups for a restore.

    -c lists the current configuration settings and exits.
       Great for confirming the current settings, and listing the databases included in the backup schedule.

    -p prune backups
       Used to manually prune backups.
       This can be used with the '-f' option, see below, to prune specific backups or sets of backups.
       Use caution when using the '-f' option.

  Verify Options:
  ================
    The verify process performs the following basic operations:
      - Start a local database server instance.
      - Restore the selected backup locally, watching for errors.
      - Run a table query on the restored database as a simple test to ensure tables were restored
        and queries against the database succeed without error.
      - Stop the local database server instance.
      - Delete the local database and configuration.

    -v <DatabaseSpec/>; in the form <Hostname/>/<DatabaseName/>/<DatabaseType/>, or <Hostname/>:<Port/>/<DatabaseName/>/<DatabaseType/>
       Triggers verify mode and starts verify mode on the specified database.

      Example:
        $0 -v postgresql:5432/TheOrgBook_Database/postgres
          - Would start the verification process on the database using the most recent backup for the database.

        $0 -v all
          - Verify the most recent backup of all databases.

    -f <BackupFileFilter/>; an OPTIONAL filter to use to find/identify the backup file to restore.
       Refer to the same option under 'Restore Options' for details.

  Restore Options:
  ================
    The restore process performs the following basic operations:
      - Drop and recreate the selected database.
      - Grant the database user access to the recreated database
      - Restore the database from the selected backup file

    Have the 'Admin' (postgres or mongodb) password handy, the script will ask you for it during the restore.

    When in restore mode, the script will list the settings it will use and wait for your confirmation to continue.
    This provides you with an opportunity to ensure you have selected the correct database and backup file
    for the job.

    Restore mode will allow you to restore a database to a different location (host, and/or database name) provided
    it can contact the host and you can provide the appropriate credentials.  If you choose to do this, you will need
    to provide a file filter using the '-f' option, since the script will likely not be able to determine which backup
    file you would want to use.  This functionality provides a convenient way to test your backups or migrate your
    database/data without affecting the original database.

    -r <DatabaseSpec/>; in the form <Hostname/>/<DatabaseName/>/<DatabaseType/>, or <Hostname/>:<Port/>/<DatabaseName/>/<DatabaseType/>
       Triggers restore mode and starts restore mode on the specified database.

      Example:
        $0 -r postgresql:5432/TheOrgBook_Database/postgres
          - Would start the restore process on the database using the most recent backup for the database.

    -f <BackupFileFilter/>; an OPTIONAL filter to use to find/identify the backup file to restore.
       This can be a full or partial file specification.  When only part of a filename is specified the restore process
       attempts to find the most recent backup matching the filter.
       If not specified, the restore process attempts to locate the most recent backup file for the specified database.

      Examples:
        $0 -r wallet-db/test_db/postgres -f wallet-db-tob_holder
          - Would try to find the latest backup matching on the partial file name provided.

        $0 -r wallet-db/test_db/postgres -f /backups/daily/2018-11-07/wallet-db-tob_holder_2018-11-07_23-59-35.sql.gz
          - Would use  the specific backup file.

        $0 -r wallet-db/test_db/postgres -f wallet-db-tob_holder_2018-11-07_23-59-35.sql.gz
          - Would use the specific backup file regardless of its location in the root backup folder.

EOF
exit 1
}
# =================================================================================================================

# =================================================================================================================
# Funtions:
# -----------------------------------------------------------------------------------------------------------------
function echoRed (){
  _msg=${1}
  _red='\e[31m'
  _nc='\e[0m' # No Color
  echo -e "${_red}${_msg}${_nc}"
}

function echoYellow (){
  _msg=${1}
  _yellow='\e[33m'
  _nc='\e[0m' # No Color
  echo -e "${_yellow}${_msg}${_nc}"
}

function echoBlue (){
  _msg=${1}
  _blue='\e[34m'
  _nc='\e[0m' # No Color
  echo -e "${_blue}${_msg}${_nc}"
}

function echoGreen (){
  _msg=${1}
  _green='\e[32m'
  _nc='\e[0m' # No Color
  echo -e "${_green}${_msg}${_nc}"
}

function echoMagenta (){
  _msg=${1}
  _magenta='\e[35m'
  _nc='\e[0m' # No Color
  echo -e "${_magenta}${_msg}${_nc}"
}

function logInfo(){
  (
    infoMsg="${1}"
    echo -e "${infoMsg}"
    postMsgToWebhook "${ENVIRONMENT_FRIENDLY_NAME}" \
                     "${ENVIRONMENT_NAME}" \
                     "INFO" \
                     "${infoMsg}"
  )
}

function logWarn(){
  (
    warnMsg="${1}"
    echoYellow "${warnMsg}"
    postMsgToWebhook "${ENVIRONMENT_FRIENDLY_NAME}" \
                     "${ENVIRONMENT_NAME}" \
                     "WARN" \
                     "${warnMsg}"
  )
}

function logError(){
  (
    errorMsg="${1}"
    echoRed "[!!ERROR!!] - ${errorMsg}" >&2
    postMsgToWebhook "${ENVIRONMENT_FRIENDLY_NAME}" \
                     "${ENVIRONMENT_NAME}" \
                     "ERROR" \
                     "${errorMsg}"
  )
}

function getWebhookPayload(){
  _payload=$(eval "cat <<-EOF
$(<${WEBHOOK_TEMPLATE})
EOF
")
  echo "${_payload}"
}

function formatWebhookMsg(){
  (
    # Escape all double quotes
    # Escape all newlines
    filters='s~"~\\"~g;:a;N;$!ba;s~\n~\\n~g;'
    _value=$(echo "${1}" | sed "${filters}")
    echo "${_value}"
  )
}

function postMsgToWebhook(){
  (
    if [ -z "${WEBHOOK_URL}" ] && [ -f ${WEBHOOK_TEMPLATE} ]; then
      return 0
    fi

    projectFriendlyName=${1}
    projectName=${2}
    statusCode=${3}
    message=$(formatWebhookMsg "${4}")
    curl -s -X POST -H 'Content-Type: application/json' --data "$(getWebhookPayload)" "${WEBHOOK_URL}" > /dev/null
  )
}

function waitForAnyKey() {
  read -n1 -s -r -p $'\e[33mWould you like to continue?\e[0m  Press Ctrl-C to exit, or any other key to continue ...' key
  echo -e \\n

  # If we get here the user did NOT press Ctrl-C ...
  return 0
}

function runOnce() {
  if [ ! -z "${RUN_ONCE}" ]; then
    return 0
  else
    return 1
  fi
}

function getDatabaseName(){
  (
    _databaseSpec=${1}
	_databaseName=$(echo ${_databaseSpec} | sed 's~^[^/]*/\(.*\)~\1~' | sed 's~\(.*\)/\(.*\)~\1~')
    echo "${_databaseName}"
  )
}

function getDatabaseType(){
  (
    _databaseSpec=${1}
    _databaseType=$(echo ${_databaseSpec} | sed 's~^[^/]*/\(.*\)~\1~' | sed 's~\(.*\)/\(.*\)~\2~' | tr '[:upper:]' '[:lower:]')
    echo "${_databaseType}"
  )
}
function getPort(){
  (
    _databaseSpec=${1}
	_databasetype=$(getDatabaseType ${_databaseSpec})
    portsed="s~\(^.*:\)\(.*\)/\(.*$\)~\2~;s~${_databaseSpec}~~g;s~/.*~~" 
   	_port=$(echo ${_databaseSpec} | sed "${portsed}") 
	
	if [ -z ${_port} ]; then
		case ${_databasetype} in
	       "postgres") 
			_port=${DEFAULT_PORT_PG}
			;;
           "mongodb") 
			_port=${DEFAULT_PORT_MD}
			;;
		   *) 
		    _configurationError=1
			_port="UNKNOWN"
			echoRed "- Unknown Database Type default port cannot be set, script will exit" >&2
			;;  
	    esac
    fi
    echo "${_port}"
  )
}

function getHostname(){
  (
    _databaseSpec=${1}
	_hostname=$(echo ${_databaseSpec} | sed 's~[:/].*~~') 
    echo "${_hostname}"
  )
}

function getHostPrefix(){
  (
    _hostname=${1}
    _hostPrefix=$(echo ${_hostname} | tr '[:lower:]' '[:upper:]' | sed "s~-~_~g")
    echo "${_hostPrefix}"
  )
}

function getHostUserParam(){
  (
    _hostname=${1}
    _hostUser=$(getHostPrefix ${_hostname})_USER
    echo "${_hostUser}"
  )
}

function getHostPasswordParam(){
  (
    _hostname=${1}
    _hostPassword=$(getHostPrefix ${_hostname})_PASSWORD
    echo "${_hostPassword}"
  )
}

function readConf(){
  (
    local OPTIND
    local readCron
    local quiet
    unset readCron
    unset quiet
    while getopts cq FLAG; do
      case $FLAG in
        c ) readCron=1 ;;
        q ) quiet=1 ;;
      esac
    done
    shift $((OPTIND-1))

    # Remove all comments and any blank lines
    filters="/^[[:blank:]]*$/d;/^[[:blank:]]*#/d;/#.*/d;"

    if [ -z "${readCron}" ]; then
      # Read in the database config ...
      #  - Remove any lines that do not match the expected database spec format(s)
      #     - <Hostname/>/<DatabaseName/>/<DatabaseType/>
      #     - <Hostname/>:<Port/>/<DatabaseName/>/<DatabaseType/>
      filters="${filters}/^[a-zA-Z0-9_/-]*\(:[0-9]*\)\?\/[a-zA-Z0-9_/-]*$/!d;"
    else
      # Read in the cron config ...
      #  - Remove any lines that MATCH expected database spec format(s),
      #    leaving, what should be, cron tabs.
      filters="${filters}/^[a-zA-Z0-9_/-]*\(:[0-9]*\)\?\/[a-zA-Z0-9_/-]*$/d;"
    fi

    if [ -f ${BACKUP_CONF} ]; then
      if [ -z "${quiet}" ]; then
        echo "Reading backup config from ${BACKUP_CONF} ..." >&2
      fi
      _value=$(sed "${filters}" ${BACKUP_CONF})
    fi

    if [ -z "${_value}" ] && [ -z "${readCron}" ]; then
      # Backward compatibility
      if [ -z "${quiet}" ]; then
        echo "Reading backup config from environment variables ..." >&2
      fi
      _value="${DATABASE_SERVICE_NAME}:${DEFAULT_PORT_PG}/${POSTGRESQL_DATABASE}"
    fi

    echo "${_value}"
  )
}


function makeDirectory()
{
  (
    # Creates directories with permissions reclusively.
    # ${1} is the directory to be created
    # Inspired by https://unix.stackexchange.com/questions/49263/recursive-mkdir
    directory="${1}"
    test $# -eq 1 || { echo "Function 'makeDirectory' can create only one directory (with it's parent directories)."; exit 1; }
    test -d "${directory}" && return 0
    test -d "$(dirname "${directory}")" || { makeDirectory "$(dirname "${directory}")" || return 1; }
    test -d "${directory}" || { mkdir --mode=g+w "${directory}" || return 1; }
    return 0
  )
}

function finalizeBackup(){
  (
    _filename=${1}
    _inProgressFilename="${_filename}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"
    _finalFilename="${_filename}${BACKUP_FILE_EXTENSION}"

    if [ -f ${_inProgressFilename} ]; then
      mv "${_inProgressFilename}" "${_finalFilename}"
      echo "${_finalFilename}"
    fi
  )
}

function ftpBackup(){
  (
    if [ -z "${FTP_URL}" ] ; then
      return 0
    fi

    _filename=${1}
    _filenameWithExtension="${_filename}${BACKUP_FILE_EXTENSION}"
    echo "Transferring ${_filenameWithExtension} to ${FTP_URL}"
    curl --ftp-ssl -T ${_filenameWithExtension} --user ${FTP_USER}:${FTP_PASSWORD} ${FTP_URL}

    if [ ${?} -eq 0 ]; then
      logInfo "Successfully transferred ${_filenameWithExtension} to the FTP server"
    else
      logError "Failed to transfer ${_filenameWithExtension} with the exit code ${?}"
    fi
  )
}

function listExistingBackups(){
  (
    local _backupDir=${1:-${ROOT_BACKUP_DIR}}
    local database

    local databases=$(readConf -q)
    local output="\nDatabase,Current Size"
    for database in ${databases}; do
      output="${output}\n${database},$(getDbSize "${database}")"
    done

    echoMagenta "\n================================================================================================================================"
    echoMagenta "Current Backups:"
    echoMagenta "\n$(echo -ne "${output}" | column -t -s ,)"
    echoMagenta "\n$(df -h ${_backupDir})"
    echoMagenta "--------------------------------------------------------------------------------------------------------------------------------"
    du -ah --time ${_backupDir}
    echoMagenta "================================================================================================================================\n"
  )
}

function getNumBackupsToRetain(){
  (
    _count=0
    _backupType=${1:-$(getBackupType)}

    case "${_backupType}" in
    daily)
      _count=${DAILY_BACKUPS}
      if (( ${_count} <= 0 )) && (( ${WEEKLY_BACKUPS} <= 0 )) && (( ${MONTHLY_BACKUPS} <= 0 )); then
        _count=1
      fi
      ;;
    weekly)
      _count=${WEEKLY_BACKUPS}
      ;;
    monthly)
      _count=${MONTHLY_BACKUPS}
      ;;
    *)
      _count=${NUM_BACKUPS}
      ;;
    esac

    echo "${_count}"
  )
}

getDirectoryName(){
  (
    local path=${1}
    path="${path%"${path##*[!/]}"}"
    local name="${path##*/}"
    echo "${name}"
  )
}

getBackupTypeFromPath(){
  (
    local path=${1}
    path="${path%"${path##*[!/]}"}"
    path="$(dirname "${path}")"
    local backupType=$(getDirectoryName "${path}")
    echo "${backupType}"
  )
}

function prune(){
  (
    local database
    local backupDirs
    local backupDir
    local backupType
    local backupTypes
    local pruneBackup
    unset backupTypes
    unset backupDirs
    unset pruneBackup

    local databases=$(readConf -q)
    if rollingStrategy; then
      backupTypes="daily weekly monthly"
      for backupType in ${backupTypes}; do
          backupDirs="${backupDirs} $(createBackupFolder -g ${backupType})"
      done
    else
      backupDirs=$(createBackupFolder -g)
    fi

    if [ ! -z "${_fromBackup}" ]; then
      pruneBackup="$(findBackup "" "${_fromBackup}")"
      while [ ! -z "${pruneBackup}" ]; do
        echoYellow "\nAbout to delete backup file: ${pruneBackup}"
        waitForAnyKey
        rm -rfvd "${pruneBackup}"

        # Quietly delete any empty directories that are left behind ...
        find ${ROOT_BACKUP_DIR} -type d -empty -delete > /dev/null 2>&1
        pruneBackup="$(findBackup "" "${_fromBackup}")"
      done
    else
      for backupDir in ${backupDirs}; do
        for database in ${databases}; do
          unset backupType
          if rollingStrategy; then
            backupType=$(getBackupTypeFromPath "${backupDir}")
          fi
          pruneBackups "${backupDir}" "${database}" "${backupType}"
        done
      done
    fi
  )
}

function pruneBackups(){
  (
    _backupDir=${1}
    _databaseSpec=${2}
    _backupType=${3:-''}
    _pruneDir="$(dirname "${_backupDir}")"
    _numBackupsToRetain=$(getNumBackupsToRetain "${_backupType}")
    _coreFilename=$(generateCoreFilename ${_databaseSpec})

    if [ -d ${_pruneDir} ]; then
      let _index=${_numBackupsToRetain}+1
      _filesToPrune=$(find ${_pruneDir}* -type f -printf '%T@ %p\n' | grep ${_coreFilename} | sort -r | tail -n +${_index} | sed 's~^.* \(.*$\)~\1~')

      if [ ! -z "${_filesToPrune}" ]; then
        echoYellow "\nPruning ${_coreFilename} backups from ${_pruneDir} ..."
        echo "${_filesToPrune}" | xargs rm -rfvd

        # Quietly delete any empty directories that are left behind ...
        find ${ROOT_BACKUP_DIR} -type d -empty -delete > /dev/null 2>&1
      fi
    fi
  )
}

function getUsername(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostUserParam ${_hostname})
    # Backward compatibility ...
    _username="${!_paramName:-${DATABASE_USER}}"
    echo ${_username}
  )
}

function getPassword(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostPasswordParam ${_hostname})
    # Backward compatibility ...
    _password="${!_paramName:-${DATABASE_PASSWORD}}"
    echo ${_password}
  )
}

function backupDatabase(){
  (
    _databaseSpec=${1}
    _fileName=${2}

    _hostname=$(getHostname ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
	_databasetype=$(getDatabaseType ${_databaseSpec})
    _port=$(getPort ${_databaseSpec})
	_username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})
	
    _backupFile="${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"

    echoGreen "\nBacking up ${_databaseSpec} ..."
	
	if [ ! -z "${_configurationError}" ]; then
       logError "\nConfiguration error!  The script will exit."
       sleep 5
       exit 1
	fi		
		
    touchBackupFile "${_backupFile}"
	
    case ${_databasetype} in
	       "postgres") 
		    echoGreen "starting Postgres backup using pg_dump....."
			PGPASSWORD=${_password} pg_dump -Fp -h "${_hostname}" -p "${_port}" -U "${_username}" "${_database}" | gzip > ${_backupFile}
			_rtnCd=${PIPESTATUS[0]}	
			;;
           "mongodb") 
		    echoGreen "starting Mongo DB backup using mongodump....."
			mongodump --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -h "${_hostname}" -u "${_username}" -p "${_password}" -d "${_database}" --quiet --gzip --archive=${_backupFile} 
			_rtnCd=${?}	
			;;
		   *) 
			echoRed "- Unknown Database Type: ${_databaseType}"
			_rtnCd=1
			;;  
	esac
    
    if (( ${_rtnCd} != 0 )); then
      rm -rfvd ${_backupFile}
    fi
    return ${_rtnCd}
	
  )
}

function touchBackupFile() {
  (
    # For safety, make absolutely certain the directory and file exist.
    # The pruning process removes empty directories, so if there is an error
    # during a backup the backup directory could be deleted.
    _backupFile=${1}
    _backupDir="${_backupFile%/*}"
    makeDirectory ${_backupDir} && touch ${_backupFile}
  )
}

function findBackup(){
  (
    _databaseSpec=${1}
    _fileName=${2}

    # If no backup file was specified, find the most recent for the database.
    # Otherwise treat the value provided as a filter to find the most recent backup file matching the filter.
    if [ -z "${_fileName}" ]; then
      _coreFilename=$(generateCoreFilename ${_databaseSpec})
      _fileName=$(find ${ROOT_BACKUP_DIR}* -type f -printf '%T@ %p\n' | grep ${_coreFilename} | sort | tail -n 1 | sed 's~^.* \(.*$\)~\1~')
    else
      _fileName=$(find ${ROOT_BACKUP_DIR}* -type f -printf '%T@ %p\n' | grep ${_fileName} | sort | tail -n 1 | sed 's~^.* \(.*$\)~\1~')
    fi

    echo "${_fileName}"
  )
}

function restoreDatabase(){
  (
    local OPTIND
    local quiet
    local localhost
    unset quiet
    unset localhost
    while getopts ql FLAG; do
      case $FLAG in
        q ) quiet=1 ;;
        l ) localhost=1 ;;
      esac
    done
    shift $((OPTIND-1))

    _databaseSpec=${1}
    _fileName=${2}
    _fileName=$(findBackup "${_databaseSpec}" "${_fileName}")

    if [ -z "${quiet}" ]; then
      echoBlue "\nRestoring database ..."
      echo -e "\nSettings:"
      echo "- Database: ${_databaseSpec}"

      if [ ! -z "${_fileName}" ]; then
        echo -e "- Backup file: ${_fileName}\n"
      else
        echoRed "- Backup file: No backup file found or specified.  Cannot continue with the restore.\n"
        exit 0
      fi
      waitForAnyKey
    fi

    _database=$(getDatabaseName ${_databaseSpec})
	_databasetype=$(getDatabaseType ${_databaseSpec})
    _username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})
	
	#set the port based on hostname and database type
    if [ -z "${localhost}" ]; then
      _hostname=$(getHostname ${_databaseSpec})
      _port=$(getPort ${_databaseSpec})
    else
      _hostname="127.0.0.1"
	  case ${_databasetype} in
	       "postgres") 
		     echo "Postgres DB using default port 5432"
			_port=${DEFAULT_PORT_PG}
			;;
           "mongodb") 
		    echo "Mongo DB using default port 27017"
			_port=${DEFAULT_PORT_MD}
			;;
		   *) 
		    _configurationError=1
			_port="UNKNOWN"
			echoRed "- Unknown Database Type default port cannot be set, script will exit"
			;;  
	   esac
    fi
	
	if [ ! -z "${_configurationError}" ]; then
       logError "\nConfiguration error!  The script will exit."
       sleep 5
       exit 1
	fi		
	
    echo "Restoring to ${_hostname}:${_port} ..."
	
	if [ -z "${quiet}" ]; then
	# Ask for the Admin Password for the database
		_msg="Admin password (${_databaseSpec}):"
		_yellow='\033[1;33m'
		_nc='\033[0m' # No Color
		_message=$(echo -e "${_yellow}${_msg}${_nc}")
		read -r -s -p $"${_message}" _adminPassword
		echo -e "\n"
	fi

	local startTime=${SECONDS}						  
	case ${_databasetype} in
	     "postgres") 
			export PGPASSWORD=${_adminPassword}
			# Wait for server ...
			_rtnCd=0
			printf "waiting for server to start"
			while ! pingDbServer ${_databaseSpec}; do
				printf "."
				local duration=$(($SECONDS - $startTime))
				if (( ${duration} >= ${DATABASE_SERVER_TIMEOUT} )); then
					echoRed "\nThe server failed to start within ${duration} seconds.\n"
					_rtnCd=1
					break
				fi
				sleep 1
			done

		   # Drop
			if (( ${_rtnCd} == 0 )); then
				psql -h "${_hostname}" -p "${_port}" -ac "DROP DATABASE \"${_database}\";"
			   _rtnCd=${?}
			    echo				
			fi

			# Create
			if (( ${_rtnCd} == 0 )); then
			  psql -h "${_hostname}" -p "${_port}" -ac "CREATE DATABASE \"${_database}\";"
			  _rtnCd=${?}
			  echo
			fi

			# Grant User Access
			if (( ${_rtnCd} == 0 )); then
			  psql -h "${_hostname}" -p "${_port}" -ac "GRANT ALL ON DATABASE \"${_database}\" TO \"${_username}\";"
			  _rtnCd=${?}
			  echo
			fi

			# Restore
			if (( ${_rtnCd} == 0 )); then
			  echo "Restoring from backup ..."
			  gunzip -c "${_fileName}" | psql -v ON_ERROR_STOP=1 -x -h "${_hostname}" -p "${_port}" -d "${_database}"
			  # Get the status code from psql specifically.  ${?} would only provide the status of the last command, psql in this case.
			  _rtnCd=${PIPESTATUS[1]}
			fi

			local duration=$(($SECONDS - $startTime))
			echo -e "Restore complete - Elapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s"\\n

			# List tables
			if [ -z "${quiet}" ] && (( ${_rtnCd} == 0 )); then
			  psql -h "${_hostname}" -p "${_port}" -d "${_database}" -c "\d"
			  _rtnCd=${?}
			fi
			;;
         "mongodb") 
          # drop database
			    echo "Restoring from backup ..."
			mongorestore --drop -u "${_username}" -p "${MONGODB_ADMIN_PASSWORD}" --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -d "${_database}" --gzip --archive=${_fileName} --nsInclude="sbc*"

			_rtnCd=${?}
			if (( ${_rtnCd} == 0 )); then
			    local duration=$(($SECONDS - $startTime))
			    echo -e "Restore complete - Elapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s"\\n
			else
				echoRed "*****mongorestor has failed"
			fi
			;;
		 *) 
		    _configurationError=1
			echoRed "- Unknown Database Type database cannot be restored, script will exit"
			;;  
	esac

    return ${_rtnCd}
  )
}

function isLastDayOfMonth(){
  (
    _date=${1:-$(date)}
    _day=$(date -d "${_date}" +%-d)
    _month=$(date -d "${_date}" +%-m)
    _lastDayOfMonth=$(date -d "${_month}/1 + 1 month - 1 day" "+%-d")

    if (( ${_day} == ${_lastDayOfMonth} )); then
      return 0
    else
      return 1
    fi
  )
}

function isLastDayOfWeek(){
  (
    # We're calling Sunday the last dayt of the week in this case.
    _date=${1:-$(date)}
    _dayOfWeek=$(date -d "${_date}" +%u)

    if (( ${_dayOfWeek} == 7 )); then
      return 0
    else
      return 1
    fi
  )
}

function getBackupType(){
  (
    _backupType=""
    if rollingStrategy; then
      if isLastDayOfMonth && (( "${MONTHLY_BACKUPS}" > 0 )); then
        _backupType="monthly"
      elif isLastDayOfWeek; then
        _backupType="weekly"
      else
        _backupType="daily"
      fi
    fi
    echo "${_backupType}"
  )
}

function createBackupFolder(){
  (
    local OPTIND
    local genOnly
    unset genOnly
    while getopts g FLAG; do
      case $FLAG in
        g ) genOnly=1 ;;
      esac
    done
    shift $((OPTIND-1))

    _backupTypeDir="${1:-$(getBackupType)}"
    if [ ! -z "${_backupTypeDir}" ]; then
      _backupTypeDir=${_backupTypeDir}/
    fi

    _backupDir="${ROOT_BACKUP_DIR}${_backupTypeDir}`date +\%Y-\%m-\%d`/"

    # Don't actually create the folder if we're just generating it for printing the configuation.
    if [ -z "${genOnly}" ]; then
      echo "Making backup directory ${_backupDir} ..." >&2
      if ! makeDirectory ${_backupDir}; then
        logError "Failed to create backup directory ${_backupDir}."
        exit 1;
      fi;
    fi

    echo ${_backupDir}
  )
}

function generateFilename(){
  (
    _backupDir=${1}
    _databaseSpec=${2}
    _coreFilename=$(generateCoreFilename ${_databaseSpec})
    _filename="${_backupDir}${_coreFilename}_`date +\%Y-\%m-\%d_%H-%M-%S`"
    echo ${_filename}
  )
}

function generateCoreFilename(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
    _coreFilename="${_hostname}-${_database}"
    echo ${_coreFilename}
  )
}

function rollingStrategy(){
  if [[ "${BACKUP_STRATEGY}" == "rolling" ]] && (( "${WEEKLY_BACKUPS}" >= 0 )) && (( "${MONTHLY_BACKUPS}" >= 0 )); then
    return 0
  else
    return 1
  fi
}

function dailyStrategy(){
  if [[ "${BACKUP_STRATEGY}" == "daily" ]] || (( "${WEEKLY_BACKUPS}" < 0 )); then
    return 0
  else
    return 1
  fi
}

function formatList(){
  (
    filters='s~^~  - ~;'
    _value=$(echo "${1}" | sed "${filters}")
    echo "${_value}"
  )
}

function listSettings(){
  _backupDirectory=${1:-$(createBackupFolder -g)}
  
  
  _databaseList=${2:-$(readConf -q)}
  _yellow='\e[33m'
  _nc='\e[0m' # No Color
  _notConfigured="${_yellow}not configured${_nc}"

  echo -e \\n"Settings:"
  _mode=$(getMode 2>/dev/null)
  echo "- Run mode: ${_mode}"
  if rollingStrategy; then
    echo "- Backup strategy: rolling"
  fi
  if dailyStrategy; then
    echo "- Backup strategy: daily"
  fi
  if ! rollingStrategy && ! dailyStrategy; then
    echoYellow "- Backup strategy: Unknown backup strategy; ${BACKUP_STRATEGY}"
    _configurationError=1
  fi
  backupType=$(getBackupType)
  if [ -z "${backupType}" ]; then
    echo "- Current backup type: flat daily"
  else
    echo "- Current backup type: ${backupType}"
  fi
  echo "- Backups to retain:"
  if rollingStrategy; then
    echo "  - Daily: $(getNumBackupsToRetain daily)"
    echo "  - Weekly: $(getNumBackupsToRetain weekly)"
    echo "  - Monthly: $(getNumBackupsToRetain monthly)"
  else
    echo "  - Total: $(getNumBackupsToRetain)"
  fi
  echo "- Backup folder: ${_backupDirectory}"
  if [[ "${_mode}" != ${ONCE} ]]; then
    if [[ "${_mode}" == ${CRON} ]] || [[ "${_mode}" == ${SCHEDULED} ]]; then
      _backupSchedule=$(readConf -cq)
      echo "- Time Zone: $(date +"%Z %z")"
    fi
    _backupSchedule=$(formatList "${_backupSchedule:-${BACKUP_PERIOD}}")
    echo "- Schedule:"
    echo "${_backupSchedule}"
  fi
  _databaseList=$(formatList "${_databaseList}")
  echo "- Databases:"
  echo "${_databaseList}"
  echo
  if [ -z "${FTP_URL}" ]; then
    echo -e "- FTP server: ${_notConfigured}"
  else
    echo "- FTP server: ${FTP_URL}"
  fi
  if [ -z "${WEBHOOK_URL}" ]; then
    echo -e "- Webhook Endpoint: ${_notConfigured}"
  else
    echo "- Webhook Endpoint: ${WEBHOOK_URL}"
  fi
  if [ -z "${ENVIRONMENT_FRIENDLY_NAME}" ]; then
    echo -e "- Environment Friendly Name: ${_notConfigured}"
  else
    echo -e "- Environment Friendly Name: ${ENVIRONMENT_FRIENDLY_NAME}"
  fi
  if [ -z "${ENVIRONMENT_NAME}" ]; then
    echo -e "- Environment Name (Id): ${_notConfigured}"
  else
    echo "- Environment Name (Id): ${ENVIRONMENT_NAME}"
  fi

  if [ ! -z "${_configurationError}" ]; then
    logError "\nConfiguration error!  The script will exit."
    sleep 5
    exit 1
  fi
  echo
}

function isInstalled(){
  rtnVal=$(type "$1" >/dev/null 2>&1)
  rtnCd=$?
  if [ ${rtnCd} -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

function cronMode(){
  (
    cronTabs=$(readConf -cq)
    if isInstalled "go-crond" && [ ! -z "${cronTabs}" ]; then
      return 0
    else
      return 1
    fi
  )
}

function isScheduled(){
  (
    if [ ! -z "${SCHEDULED_RUN}" ]; then
      return 0
    else
      return 1
    fi
  )
}

function restoreMode(){
  (
    if [ ! -z "${_restoreDatabase}" ]; then
      return 0
    else
      return 1
    fi
  )
}

function verifyMode(){
  (
    if [ ! -z "${_verifyBackup}" ]; then
      return 0
    else
      return 1
    fi
  )
}

function pruneMode(){
  (
    if [ ! -z "${RUN_PRUNE}" ]; then
      return 0
    else
      return 1
    fi
  )
}

function getMode(){
  (
    unset _mode

    if pruneMode; then
      _mode="${PRUNE}"
    fi

    if [ -z "${_mode}" ] && restoreMode; then
      _mode="${RESTORE}"
    fi

    if [ -z "${_mode}" ] && verifyMode; then
      # Determine if this is a scheduled verification or a manual one.
      if isScheduled; then
        if cronMode; then
          _mode="${SCHEDULED_VERIFY}"
        else
          _mode="${ERROR}"
          logError "Scheduled mode cannot be used without cron being installed and at least one cron tab being defined in ${BACKUP_CONF}."
        fi
      else
        _mode="${VERIFY}"
      fi
    fi

    if [ -z "${_mode}" ] && runOnce; then
      _mode="${ONCE}"
    fi

    if [ -z "${_mode}" ] && isScheduled; then
      if cronMode; then
        _mode="${SCHEDULED}"
      else
        _mode="${ERROR}"
        logError "Scheduled mode cannot be used without cron being installed and at least one cron tab being defined in ${BACKUP_CONF}."
      fi
    fi

    if [ -z "${_mode}" ] && cronMode; then
      _mode="${CRON}"
    fi

    if [ -z "${_mode}" ]; then
      _mode="${LEGACY}"
    fi

    echo "${_mode}"
  )
}

function runBackups(){
  (
    echoBlue "\nStarting backup process ..."
    databases=$(readConf)
    backupDir=$(createBackupFolder)
    #listSettings "${backupDir}" "${databases}"
	
    for database in ${databases}; do

      local startTime=${SECONDS}
      filename=$(generateFilename "${backupDir}" "${database}")
      backupDatabase "${database}" "${filename}"
      rtnCd=${?}
      local duration=$(($SECONDS - $startTime))
      local elapsedTime="\n\nElapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s - Status Code: ${rtnCd}"

      if (( ${rtnCd} == 0 )); then
         backupPath=$(finalizeBackup "${filename}")
         dbSize=$(getDbSize "${database}")
         backupSize=$(getFileSize "${backupPath}")
         logInfo "Successfully backed up ${database}.\nBackup written to ${backupPath}.\nDatabase Size: ${dbSize}\nBackup Size: ${backupSize}${elapsedTime}"
         ftpBackup "${filename}"
         pruneBackups "${backupDir}" "${database}"
      else
         logError "Failed to backup ${database}.${elapsedTime}"
      fi
    done

    listExistingBackups ${ROOT_BACKUP_DIR}
  )
}

function startCron(){
  logInfo "Starting backup server in cron mode ..."
  listSettings
  echoBlue "Starting go-crond as a forground task ...\n"
  CRON_CMD="go-crond -v --allow-unprivileged ${BACKUP_CONF}"
  exec ${CRON_CMD}
}

function startLegacy(){
  (
    while true; do
      runBackups

      echoYellow "Sleeping for ${BACKUP_PERIOD} ...\n"
      sleep ${BACKUP_PERIOD}
    done
  )
}

function startServer(){
  (
    _databaseSpec=${1}
	_databasetype=$(getDatabaseType ${_databaseSpec})
	
	case ${_databasetype} in
	     "postgres") 
			# Start a local PostgreSql instance
			POSTGRESQL_DATABASE=$(getDatabaseName "${_databaseSpec}") \
			POSTGRESQL_USER=$(getUsername "${_databaseSpec}") \
			POSTGRESQL_PASSWORD=$(getPassword "${_databaseSpec}") \
			run-postgresql >/dev/null 2>&1 &
			;;
         "mongodb") 
		    #echo "Mongo DB using default port 27017"
      export MONGODB_ADMIN_PASSWORD="${DATABASE_PASSWORD}"
			/usr/bin/run-mongod >/dev/null 2>&1 &

      mkfifo /tmp/fifo || exit
      trap 'rm -f /tmp/fifo' 0

      /usr/bin/run-mongod &> /tmp/fifo &

while read line; do
    case $line in
        "waiting for connections on port 27017") echo "Y found, breaking out."; break;;
        *) printf "." ;;
    esac
done < /tmp/fifo
			;;
		 *) 
		    _configurationError=1
			echoRed "- Unknown Database Type database cannot be started, script will exit"
			;;  
	esac
	
    # Wait for server to start ...
    local startTime=${SECONDS}
    rtnCd=0
    printf "waiting for server to start"
    while ! pingDbServer ${_databaseSpec}; do
      printf "."
      local duration=$(($SECONDS - $startTime))
      if (( ${duration} >= ${DATABASE_SERVER_TIMEOUT} )); then
        echoRed "\nThe server failed to start within ${duration} seconds.\n"
        rtnCd=1
        break
      fi
      sleep 1
    done

    return ${rtnCd}
  )
}

function stopServer(){
  (
    _databaseSpec=${1}
	_databasetype=$(getDatabaseType ${_databaseSpec})	
  
 	case ${_databasetype} in
	     "postgres") 
			# Stop the local PostgreSql instance
			pg_ctl stop -D /var/lib/pgsql/data/userdata

			# Delete the database files and configuration
			echo -e "Cleaning up ...\n" >&2
			rm -rf /var/lib/pgsql/data/userdata
			;;
         "mongodb") 
		    #echo "Mongo DB using default port 27017"
			sleep 10
			mongod --dbpath=/var/lib/mongodb/data --shutdown
			
			# Delete the database files and configuration
			echo -e "Cleaning up ...\n" >&2
			rm -rf  /var/lib/mongodb/data/*
			;;
		 *) 
		    _configurationError=1
			echoRed "- Unknown Database Type database cannot be started, script will exit"
			;;  
	esac	 

  )
}

function pingDbServer(){
  (
    _databaseSpec=${1}
	_databasetype=$(getDatabaseType ${_databaseSpec})	
    _database=$(getDatabaseName "${_databaseSpec}")
    _username=$(getUsername ${_databaseSpec})
	_password=$(getPassword ${_databaseSpec})
	unset _configurationError
	
	#Set the port based on the database type
    if [ -z "${localhost}" ]; then
      _hostname=$(getHostname ${_databaseSpec})
      _port=$(getPort ${_databaseSpec})
    else
      _hostname="127.0.0.1"
	  case ${_databasetype} in
	   "postgres") 
		_port=${DEFAULT_PORT_PG}
		;;
	   "mongodb") 
		_port=${DEFAULT_PORT_MD}
		;;
	   *) 
		_configurationError=1
		_port="UNKNOWN"
		echoRed "- Unknown Database Type default port cannot be set, script will exit" >&2
		return 1
		;;  
	  esac
    fi
	
	if [ -z "${_configurationError}" ]; then
		case ${_databasetype} in
			 "postgres") 
				if psql -h ${_hostname} -U ${_username} -q -d ${_database} -c 'SELECT 1' >/dev/null 2>&1; then
					return 0
				else
					return 1
				fi
				;;
			 "mongodb") 
				if mongo -h "${_hostname}" --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -u "${_username}" -p "${_password}" --port "${_port}" --quiet --eval 'db.runCommand({ connectionStatus: 1 })' >/dev/null 2>&1; then			
					return 0
				else
					return 1
				fi
				;;
			 *) 
				_configurationError=1
				echoRed "- Unknown Database Type database cannot be pinged, script will exit"
				return 1
				;;  
		esac
	fi
	
  )
}

function verifyBackups(){
  (
    local OPTIND
    local flags
    unset flags
    while getopts q FLAG; do
      case $FLAG in
        * ) flags+="-${FLAG} " ;;
      esac
    done
    shift $((OPTIND-1))

    _databaseSpec=${1}
    _fileName=${2}
    if [[ "${_databaseSpec}" == "all" ]]; then
      databases=$(readConf -q)
    else
      databases=${_databaseSpec}
    fi

    for database in ${databases}; do
      verifyBackup ${flags} "${database}" "${_fileName}"
    done
  )
}

function verifyBackup(){
  (
    local OPTIND
    local quiet
    unset quiet
    while getopts q FLAG; do
      case $FLAG in
        q ) quiet=1 ;;
      esac
    done
    shift $((OPTIND-1))

    _databaseSpec=${1}
	_database=$(getDatabaseName ${_databaseSpec})	
	_databasetype=$(getDatabaseType ${_databaseSpec})
    _username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})

	_fileName=${2}
    _fileName=$(findBackup "${_databaseSpec}" "${_fileName}")

    echoBlue "\nVerifying backup ..."
    echo -e "\nSettings:"
    echo "- Database: ${_databaseSpec}"

    if [ ! -z "${_fileName}" ]; then
      echo -e "- Backup file: ${_fileName}\n"
    else
      echoRed "- Backup file: No backup file found or specified.  Cannot continue with the backup verification.\n"
      exit 0
    fi

    if [ -z "${quiet}" ]; then
      waitForAnyKey
    fi

    local startTime=${SECONDS}
	startServer "${_databaseSpec}"
	rtnCd=${?}

    # Restore the database
    if (( ${rtnCd} == 0 )); then
      echo
      echo "Restoring from backup ..."
      if [ -z "${quiet}" ]; then
        restoreDatabase -ql "${_databaseSpec}" "${_fileName}" 
        rtnCd=${?}
      else
        # Filter out stdout, keep stderr
        restoreLog=$(restoreDatabase -ql "${_databaseSpec}" "${_fileName}" 2>&1 >/dev/null)
        rtnCd=${?}

        if [ ! -z "${restoreLog}" ]; then
          restoreLog="\n\nThe following issues were encountered during backup verification;\n${restoreLog}"
        fi
      fi
    fi

    # Ensure there are tables in the databse and general queries work
    if (( ${rtnCd} == 0 )); then
	    _hostname="127.0.0.1"
		case ${_databasetype} in
	     "postgres") 
			_port="${DEFAULT_PORT_PG}"
			tables=$(psql -h "${_hostname}" -p "${_port}" -d "${_database}" -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema='${TABLE_SCHEMA}' AND table_type='BASE TABLE';")
			;;
         "mongodb") 
         echo 
			collections=$(mongo ${_hostname}/${_database} --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -u "${_username}" -p "${_password}" --quiet --eval 'var dbs = [];dbs = db.getCollectionNames();for (i in dbs){ print(db.dbs[i]);}';)			
			;;			
		 *) 
			;;  
		esac
    rtnCd=${?}
    fi

    # Get the size of the restored database
    if (( ${rtnCd} == 0 )); then
      size=$(getDbSize -l "${_databaseSpec}")
      rtnCd=${?}
    fi

    if (( ${rtnCd} == 0 )); then
	   case ${_databasetype} in
	        "postgres") 
				numResults=$(echo "${tables}"| wc -l)
				if [[ ! -z "${tables}" ]] && (( numResults >= 1 )); then
					# All good
					verificationLog="\nThe restored database contained ${numResults} tables, and is ${size} in size."
				else
					# Not so good
					verificationLog="\nNo tables were found in the restored database."
					rtnCd="3"
				fi
				;;
			"mongodb") 
				# 
				numResults=$(echo "${collections}"| wc -l)
				if [[ ! -z "${collections}" ]] && (( numResults >= 1 )); then
					# All good
					verificationLog="\nThe restored database contained ${numResults} collections, and is ${size} in size."
				else
					# Not so good
					verificationLog="\nNo collections were found in the restored database {_database}."
					rtnCd="3"
				fi				
				;;
			*) 
				;;  
		esac	  
    fi

	#Stop the database server
	stopServer "${_databaseSpec}"
    local duration=$(($SECONDS - $startTime))
    local elapsedTime="\n\nElapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s - Status Code: ${rtnCd}"

    if (( ${rtnCd} == 0 )); then
      logInfo "Successfully verified backup; ${_fileName}${verificationLog}${restoreLog}${elapsedTime}"
    else
      logError "Backup verification failed; ${_fileName}${verificationLog}${restoreLog}${elapsedTime}"
    fi

    return ${rtnCd}
  )
}

function getFileSize(){
  (
    _filename=${1}
    echo $(du -h "${_filename}" | awk '{print $1}')
  )
}

function getDbSize(){
  (
    local OPTIND
    local localhost
    unset localhost
    while getopts l FLAG; do
      case $FLAG in
        l ) localhost=1 ;;
      esac
    done
    shift $((OPTIND-1))

    _databaseSpec=${1}
    _database=$(getDatabaseName ${_databaseSpec})
	_databasetype=$(getDatabaseType ${_databaseSpec})
    _username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})
	
	#Set the port based on the database type
    if [ -z "${localhost}" ]; then
      _hostname=$(getHostname ${_databaseSpec})
      _port=$(getPort ${_databaseSpec})
    else
      _hostname="127.0.0.1"
	  case ${_databasetype} in
	   "postgres") 
		_port=${DEFAULT_PORT_PG}
		;;
	   "mongodb") 
		_port=${DEFAULT_PORT_MD}
		;;
	   *) 
		_configurationError=1
		_port="UNKNOWN"
		echoRed "- Unknown Database Type default port cannot be set, script will exit" >&2
		;;  
	  esac
    fi

	#Run the sql query based on each database type
	case ${_databasetype} in
	   "postgres") 
		if isInstalled "psql"; then
			size=$(PGPASSWORD=${_password} psql -h "${_hostname}" -p "${_port}" -U "${_username}" -t -c "SELECT pg_size_pretty(pg_database_size(current_database())) as size;")
			rtnCd=${?}
		else
			size="psql not found"
			rtnCd=1
		fi
		;;
	   "mongodb") 
		if isInstalled "mongo"; then
           if [ -z "${localhost}" ]; then
              size=$(mongo ${_hostname}/${_database} --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -u "${_username}" -p "${_password}" --quiet --eval 'printjson(db.stats().fsTotalSize)')
           else
              size=$(mongo ${_hostname}/${_database} --authenticationDatabase="${MONGODB_AUTHENTICATION_DATABASE}" -u "${_username}" -p "${_password}" --quiet --eval 'printjson(db.stats().fsTotalSize)')
           fi		
           rtnCd=${?}
		else
			size="mongo not found"
			rtnCd=1
		fi
		;;
	   *) 
		;;  
	esac

    echo "${size}"
    return ${rtnCd}
  )
}
# ======================================================================================

# ======================================================================================
# Set Defaults
# --------------------------------------------------------------------------------------
export BACKUP_FILE_EXTENSION=".sql.gz"
export IN_PROGRESS_BACKUP_FILE_EXTENSION=".sql.gz.in_progress"
export DEFAULT_PORT_PG=${POSTGRESQL_PORT_NUM:-5432}
export DEFAULT_PORT_MD=${MONGO_PORT_NUM:-27017}
export DATABASE_SERVICE_NAME=${DATABASE_SERVICE_NAME:-postgresql}
export POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE:-my_postgres_db}
export MONGODB_AUTHENTICATION_DATABASE=${MONGODB_AUTHENTICATION_DATABASE:-admin}
export TABLE_SCHEMA=${TABLE_SCHEMA:-public}


# Supports:
# - daily
# - rolling
export BACKUP_STRATEGY=$(echo "${BACKUP_STRATEGY:-daily}" | tr '[:upper:]' '[:lower:]')
export BACKUP_PERIOD=${BACKUP_PERIOD:-1d}
export ROOT_BACKUP_DIR=${ROOT_BACKUP_DIR:-${BACKUP_DIR:-/backups/}}
export BACKUP_CONF=${BACKUP_CONF:-backup.conf}

# Used to prune the total number of backup when using the daily backup strategy.
# Default provides for one full month of backups
export NUM_BACKUPS=${NUM_BACKUPS:-31}

# Used to prune the total number of backup when using the rolling backup strategy.
# Defaults provide for:
# - A week's worth of daily backups
# - A month's worth of weekly backups
# - The previous month's backup
export DAILY_BACKUPS=${DAILY_BACKUPS:-6}
export WEEKLY_BACKUPS=${WEEKLY_BACKUPS:-4}
export MONTHLY_BACKUPS=${MONTHLY_BACKUPS:-1}

# Webhook defaults
WEBHOOK_TEMPLATE=${WEBHOOK_TEMPLATE:-webhook-template.json}

# Modes:
export ONCE="once"
export SCHEDULED="scheduled"
export RESTORE="restore"
export VERIFY="verify"
export CRON="cron"
export LEGACY="legacy"
export ERROR="error"
export SCHEDULED_VERIFY="scheduled-verify"
export PRUNE="prune"

# Other:
export DATABASE_SERVER_TIMEOUT=${DATABASE_SERVER_TIMEOUT:-60}
# ======================================================================================

# =================================================================================================================
# Initialization:
# -----------------------------------------------------------------------------------------------------------------
while getopts clr:v:f:1sph FLAG; do
  case $FLAG in
    c)
      echoBlue "\nListing configuration settings ..."
      listSettings
      exit 0
      ;;
    l)
      listExistingBackups ${ROOT_BACKUP_DIR}
      exit 0
      ;;
    r)
      # Trigger restore mode ...
      export _restoreDatabase=${OPTARG}
      ;;
    v)
      # Trigger verify mode ...
      export _verifyBackup=${OPTARG}
      ;;
    f)
      # Optionally specify the backup file to verify or restore from ...
      export _fromBackup=${OPTARG}
      ;;
    1)
      export RUN_ONCE=1
      ;;
    s)
      export SCHEDULED_RUN=1
      ;;
    p)
      export RUN_PRUNE=1
      ;;
    h)
      usage
      ;;
    \?)
      echo -e \\n"Invalid option: -${OPTARG}"\\n
      usage
      ;;
  esac
done
shift $((OPTIND-1))
# =================================================================================================================

# =================================================================================================================
# Main Script
# -----------------------------------------------------------------------------------------------------------------
case $(getMode) in
  ${ONCE})
    runBackups
    echoGreen "Single backup run complete.\n"
    ;;

  ${SCHEDULED})
    runBackups
    echoGreen "Scheduled backup run complete.\n"
    ;;

  ${RESTORE})
    restoreDatabase "${_restoreDatabase}" "${_fromBackup}"
    ;;

  ${VERIFY})
    verifyBackups "${_verifyBackup}" "${_fromBackup}"
    ;;

  ${SCHEDULED_VERIFY})
    verifyBackups -q "${_verifyBackup}" "${_fromBackup}"
    ;;

  ${CRON})
    startCron
    ;;

  ${LEGACY})
    startLegacy
    ;;

  ${PRUNE})
    prune
    ;;

  ${ERROR})
    echoRed "A configuration error has occurred, review the details above."
    usage
    ;;
  *)
    echoYellow "Unrecognized operational mode; ${_mode}"
    usage
    ;;
esac
# =================================================================================================================