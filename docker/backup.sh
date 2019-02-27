  #!/bin/bash

# =================================================================================================================
# Usage:
# -----------------------------------------------------------------------------------------------------------------
function usage () {
  cat <<-EOF

  Automated backup script for Postgresql databases

  Refer to the project documentation for additional details on how to use this script.
  - https://github.com/BCDevOps/backup-container

  Usage:
    $0 [options]

  Standard Options:
  ========
    -h prints this usage documentation.
    
    -1 run once.
       Performs a single set of backups and exits.

    -s run scheduled.
       Performs simular to run once.  A flag to be used by cron scheduled backups to indicate they are being run on a schedule.

    -l lists existing backups.
       Great for listing the available backups for a restore.

    -c lists the current configuration settings and exits.
       Great for confirming the current settings, and listing the databases included in the backup schedule.

  Restore Options:
  ========
    The restore process performs the following basic operations:
      - Drop and recreate the selected database.
      - Grant the database user access to the recreated database
      - Restore the database from the selected backup file

    Have the 'Admin' (postgres) password handy, the script will ask you for it during the restore.

    When in restore mode, the script will list the settings it will use and wait for your confirmation to continue.
    This provides you with an opportunity to ensure you have selected the correct database and backup file
    for the job.

    Restore mode will allow you to restore a database to a different location (host, and/or database name) provided 
    it can contact the host and you can provide the appropriate credentials.  If you choose to do this, you will need 
    to provide a file filter using the '-f' option, since the script will likely not be able to determine which backup 
    file you would want to use.  This functionality provides a convenient way to test your backups or migrate your
    database/data whithout affecting the original database.

    -r <DatabaseSpec/>; in the form <Hostname/>/<DatabaseName/>, or <Hostname/>:<Port/>/<DatabaseName/>
       Triggers restore mode and starts restore mode on the specified database.

      Example:
        $0 -r postgresql:5432/TheOrgBook_Database
          - Would start the restore process on the database using the most recent backup for the database.
 
    -f <BackupFileFilter/>; the filter to use to find/identify the backup file to restore.
       This can be a full or partial file specification.  When only part of a filename is specified the restore process
       attempts to find the most recent backup matching the filter.
       If not specified, the restore process attempts to locate the most recent backup file for the specified database.

      Examples:
        $0 -r wallet-db/test_db -f wallet-db-tob_holder
          - Would try to find the latest backup matching on the partial file name provided.
        
        $0 -r wallet-db/test_db -f /backups/daily/2018-11-07/wallet-db-tob_holder_2018-11-07_23-59-35.sql.gz
          - Would use  the specific backup file.
        
        $0 -r wallet-db/test_db -f wallet-db-tob_holder_2018-11-07_23-59-35.sql.gz
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
    echo "${infoMsg}"
    postMsgToWebhook "${ENVIRONMENT_FRIENDLY_NAME}" \
                     "${ENVIRONMENT_NAME}" \
                     "INFO" \
                     "${infoMsg}"
  )
}

function logError(){
  (
    errorMsg="${1}"
    echoRed "[!!ERROR!!] - ${errorMsg}"
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

function postMsgToWebhook(){
  (
    if [ -z "${WEBHOOK_URL}" ] && [ -f ${WEBHOOK_TEMPLATE} ]; then
      return 0
    fi

    projectFriendlyName=${1}
    projectName=${2}
    statusCode=${3}
    message=${4}
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
    _databaseName=$(echo ${_databaseSpec} | sed 's~^.*/\(.*$\)~\1~')
    echo "${_databaseName}"
  )
}

function getPort(){
  (
    _databaseSpec=${1}
    _port=$(echo ${_databaseSpec} | sed "s~\(^.*:\)\(.*\)/\(.*$\)~\2~;s~${_databaseSpec}~~g;")
    if [ -z ${_port} ]; then
      _port=${DEFAULT_PORT}
    fi
    echo "${_port}"
  )
}

function getHostname(){
  (
    _databaseSpec=${1}
    _hostname=$(echo ${_databaseSpec} | sed 's~\(^.*\)/.*$~\1~;s~\(^.*\):.*$~\1~;')
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
    readCron=${1}

    # Remove all comments and any blank lines
    filters="/^[[:blank:]]*$/d;/^[[:blank:]]*#/d;/#.*/d;"

    if [ -z "${readCron}" ]; then
      # Read in the database config ...
      #  - Remove any lines that do not match the expected database spec format(s)
      #     - <Hostname/>/<DatabaseName/>
      #     - <Hostname/>:<Port/>/<DatabaseName/>
      filters="${filters}/^[a-zA-Z0-9_/-]*\(:[0-9]*\)\?\/[a-zA-Z0-9_/-]*$/!d;"
    else
      # Read in the cron config ...
      #  - Remove any lines that MATCH expected database spec format(s), 
      #    leaving, what should be, cron tabs.
      filters="${filters}/^[a-zA-Z0-9_/-]*\(:[0-9]*\)\?\/[a-zA-Z0-9_/-]*$/d;"
    fi

    if [ -f ${BACKUP_CONF} ]; then
      echo "Reading backup config from ${BACKUP_CONF} ..." >&2
      _value=$(sed "${filters}" ${BACKUP_CONF})
    fi

    if [ -z "${_value}" ] && [ -z "${readCron}" ]; then
      # Backward compatibility
      echo "Reading backup config from environment variables ..." >&2
      _value="${DATABASE_SERVICE_NAME}:${DEFAULT_PORT}/${POSTGRESQL_DATABASE}"
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
      logInfo "Backup written to ${_finalFilename} ..."
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
    _backupDir=${1:-${ROOT_BACKUP_DIR}}
    echoMagenta "\n================================================================================================================================"
    echoMagenta "Current Backups:"
    echoMagenta "--------------------------------------------------------------------------------------------------------------------------------"
    du -ah --time ${_backupDir}
    echoMagenta "================================================================================================================================\n"
  )
}

function getNumBackupsToRetain(){
  (
    _count=0
    _backupType=$(getBackupType)

    case "${_backupType}" in
    daily)
      _count=${DAILY_BACKUPS}
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

function pruneBackups(){
  (
    _backupDir=${1}
    _databaseSpec=${2}
    _pruneDir="$(dirname "${_backupDir}")"
    _numBackupsToRetain=$(getNumBackupsToRetain)
    _coreFilename=$(generateCoreFilename ${_databaseSpec})

    let _index=${_numBackupsToRetain}+1
    _filesToPrune=$(find ${_pruneDir}* -type f -printf '%T@ %p\n' | grep ${_coreFilename} | sort -r | tail -n +${_index} | sed 's~^.* \(.*$\)~\1~')

    if [ ! -z "${_filesToPrune}" ]; then
      echoYellow "\nPruning ${_coreFilename} backups from ${_pruneDir} ..."
      echo "${_filesToPrune}" | xargs rm -rfvd

      # Quietly delete any empty directories that are left behind ...
      find ${ROOT_BACKUP_DIR} -type d -empty -delete > /dev/null 2>&1
    fi
  )
}

function getUsername(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostUserParam ${_hostname})
    # Backward compatibility ...
    _username="${!_paramName:-${POSTGRESQL_USER}}"
    echo ${_username}
  )
}

function getPassword(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostPasswordParam ${_hostname})
    # Backward compatibility ...
    _password="${!_paramName:-${POSTGRESQL_PASSWORD}}"
    echo ${_password}
  )
}

function backupDatabase(){
  (
    _databaseSpec=${1}
    _fileName=${2}

    _hostname=$(getHostname ${_databaseSpec})
    _port=$(getPort ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
    _username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})
    _backupFile="${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"

    echoGreen "\nBacking up ${_databaseSpec} ..."

    export PGPASSWORD=${_password}
    SECONDS=0
    touchBackupFile "${_backupFile}"
    
    pg_dump -Fp -h "${_hostname}" -p "${_port}" -U "${_username}" "${_database}" | gzip > ${_backupFile}
    # Get the status code from pg_dump.  ${?} would provide the status of the last command, gzip in this case.
    _rtnCd=${PIPESTATUS[0]}

    if (( ${_rtnCd} != 0 )); then
      rm -rfvd ${_backupFile}
    fi

    duration=$SECONDS
    echo "Elapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s - Status Code: ${_rtnCd}"
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

function restoreDatabase(){
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

    _hostname=$(getHostname ${_databaseSpec})
    _port=$(getPort ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
    _username=$(getUsername ${_databaseSpec})
    _password=$(getPassword ${_databaseSpec})

    # Ask for the Admin Password for the database
    _msg="Admin password (${_databaseSpec}):"
    _yellow='\033[1;33m'
    _nc='\033[0m' # No Color
    _message=$(echo -e "${_yellow}${_msg}${_nc}")
    read -r -s -p $"${_message}" _adminPassword
    echo -e "\n"

    export PGPASSWORD=${_adminPassword}
    SECONDS=0

    # Drop
    psql -h "${_hostname}" -p "${_port}" -ac "DROP DATABASE \"${_database}\";"
    echo

    # Create
    psql -h "${_hostname}" -p "${_port}" -ac "CREATE DATABASE \"${_database}\";"
    echo

    # Grant User Access
    psql -h "${_hostname}" -p "${_port}" -ac "GRANT ALL ON DATABASE \"${_database}\" TO \"${_username}\";"
    echo

    # Restore
    echo "Restoring from backup ..."
    gunzip -c "${_fileName}" | psql -h "${_hostname}" -p "${_port}" -d "${_database}"

    duration=$SECONDS
    echo -e "Restore complete - Elapsed time: $(($duration/3600))h:$(($duration%3600/60))m:$(($duration%60))s"\\n

    # List tables
    psql -h "${_hostname}" -p "${_port}" -d "${_database}" -c "\d"
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
    genOnly=${1}

    _backupTypeDir="$(getBackupType)"
    if [ ! -z "${_backupTypeDir}" ]; then
      _backupTypeDir=${_backupTypeDir}/
    fi

    _backupDir="${ROOT_BACKUP_DIR}${_backupTypeDir}`date +\%Y-\%m-\%d`/"

    # Don't actually create the folder if we're just generating it for printing the configuation.
    if [ -z "${genOnly}" ]; then
      echo "Making backup directory ${_backupDir} ..." >&2
      if ! makeDirectory ${_backupDir}; then
        echo $(logError "Failed to create backup directory ${_backupDir}.") >&2
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
  if [[ "${BACKUP_STRATEGY}" == "rolling" ]] && (( "${WEEKLY_BACKUPS}" > 0 )) && (( "${MONTHLY_BACKUPS}" >= 0 )); then
    return 0
  else
    return 1
  fi
}

function dailyStrategy(){
  if [[ "${BACKUP_STRATEGY}" == "daily" ]] || (( "${WEEKLY_BACKUPS}" <= 0 )); then
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
  _backupDirectory=${1}
  _databaseList=${2}
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
    echo "- Backup type: flat daily"
  else
    echo "- Backup type: ${backupType}"
  fi
  echo "- Number of each backup to retain: $(getNumBackupsToRetain)"
  echo "- Backup folder: ${_backupDirectory}"
  if [[ "${_mode}" != ${ONCE} ]]; then
    if [[ "${_mode}" == ${CRON} ]] || [[ "${_mode}" == ${SCHEDULED} ]]; then
      _backupSchedule=$(readConf 1 2>/dev/null)
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
    cronTabs=$(readConf 1 2>/dev/null)
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

function getMode(){
  (
    unset _mode

    if [ -z "${_mode}" ] && restoreMode; then
      _mode="${RESTORE}"
    fi

    if [ -z "${_mode}" ] && runOnce; then
      _mode="${ONCE}"
    fi

    if [ -z "${_mode}" ] && isScheduled; then
      _mode="${SCHEDULED}"
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
    listSettings "${backupDir}" "${databases}"

    for database in ${databases}; do
      filename=$(generateFilename "${backupDir}" "${database}")
      if backupDatabase "${database}" "${filename}"; then
        finalizeBackup "${filename}"
        ftpBackup "${filename}"
        pruneBackups "${backupDir}" "${database}"
      else
        logError "Failed to backup ${database}."
      fi
    done

    listExistingBackups ${ROOT_BACKUP_DIR}
  )
}

function startCron(){
  echo "Starting go-crond as a forground task ..."
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
# ======================================================================================

# ======================================================================================
# Set Defaults
# --------------------------------------------------------------------------------------
export BACKUP_FILE_EXTENSION=".sql.gz"
export IN_PROGRESS_BACKUP_FILE_EXTENSION=".sql.gz.in_progress"
export DEFAULT_PORT=${POSTGRESQL_PORT_NUM:-5432}
export DATABASE_SERVICE_NAME=${DATABASE_SERVICE_NAME:-postgresql}
export POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE:-my_postgres_db}

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
export CRON="cron"
export LEGACY="legacy"
# ======================================================================================

# =================================================================================================================
# Initialization:
# -----------------------------------------------------------------------------------------------------------------
while getopts clr:f:1sh FLAG; do
  case $FLAG in
    c)
      echoBlue "\nListing configuration settings ..."
      databases=$(readConf)
      backupDir=$(createBackupFolder 1)
      listSettings "${backupDir}" "${databases}"
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
    f)
      # Optionally specify the backup file to restore from ...
      export _fromBackup=${OPTARG}
      ;;
    1)
      export RUN_ONCE=1
      ;;
    s)
      export SCHEDULED_RUN=1
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

  ${CRON})
    startCron
    ;;

  ${LEGACY})
    startLegacy
    ;;

  *)
    echoWarning "Unrecognized operational mode; ${_cmd}"
    usage
    ;;
esac
# =================================================================================================================
