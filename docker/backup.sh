#!/bin/bash

# =================================================================================================================
# Usage:
# -----------------------------------------------------------------------------------------------------------------
usage () {
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
echoRed (){
  _msg=${1}
  _red='\e[31m'
  _nc='\e[0m' # No Color
  echo -e "${_red}${_msg}${_nc}"
}

echoYellow (){
  _msg=${1}
  _yellow='\e[33m'
  _nc='\e[0m' # No Color
  echo -e "${_yellow}${_msg}${_nc}"
}

echoBlue (){
  _msg=${1}
  _blue='\e[34m'
  _nc='\e[0m' # No Color
  echo -e "${_blue}${_msg}${_nc}"
}

echoGreen (){
  _msg=${1}
  _green='\e[32m'
  _nc='\e[0m' # No Color
  echo -e "${_green}${_msg}${_nc}"
}

echoMagenta (){
  _msg=${1}
  _magenta='\e[35m'
  _nc='\e[0m' # No Color
  echo -e "${_magenta}${_msg}${_nc}"
}

waitForAnyKey() {
  read -n1 -s -r -p $'\e[33mWould you like to continue?\e[0m  Press Ctrl-C to exit, or any other key to continue ...' key
  echo -e \\n

  # If we get here the user did NOT press Ctrl-C ...
  return 0
}

runOnce() {
  if [ ! -z "${RUN_ONCE}" ]; then
    return 0
  else
    return 1
  fi
}

getDatabaseName(){
  (
    _databaseSpec=${1}
    _databaseName=$(echo ${_databaseSpec} | sed 's~^.*/\(.*$\)~\1~')
    echo "${_databaseName}"
  )
}

getPort(){
  (
    _databaseSpec=${1}
    _port=$(echo ${_databaseSpec} | sed "s~\(^.*:\)\(.*\)/\(.*$\)~\2~;s~${_databaseSpec}~~g;")
    if [ -z ${_port} ]; then
      _port=${DEFAULT_PORT}
    fi
    echo "${_port}"
  )
}

getHostname(){
  (
    _databaseSpec=${1}
    _hostname=$(echo ${_databaseSpec} | sed 's~\(^.*\)/.*$~\1~;s~\(^.*\):.*$~\1~;')
    echo "${_hostname}"
  )
}

getHostPrefix(){
  (
    _hostname=${1}
    _hostPrefix=$(echo ${_hostname} | tr '[:lower:]' '[:upper:]' | sed "s~-~_~g")
    echo "${_hostPrefix}"
  )
}

getHostUserParam(){
  (
    _hostname=${1}
    _hostUser=$(getHostPrefix ${_hostname})_USER
    echo "${_hostUser}"
  )
}

getHostPasswordParam(){
  (
    _hostname=${1}
    _hostPassword=$(getHostPrefix ${_hostname})_PASSWORD
    echo "${_hostPassword}"
  )
}

readConf(){
  (
    if [ -f ${BACKUP_CONF} ]; then
      # Read in the config minus any comments ...
      echo "Reading backup config from ${BACKUP_CONF} ..." >&2
      _value=$(sed '/^[[:blank:]]*#/d;s/#.*//' ${BACKUP_CONF})
    fi

    if [ -z "${_value}" ]; then
      # Backward compatibility
      echo "Reading backup config from environment variables ..." >&2
      _value="${DATABASE_SERVICE_NAME}:${DEFAULT_PORT}/${POSTGRESQL_DATABASE}"
    fi
  echo "${_value}"
  )
}

makeDirectory()
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

finalizeBackup(){
  (
    _filename=${1}
    _inProgressFilename="${_filename}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"
    _finalFilename="${_filename}${BACKUP_FILE_EXTENSION}"

    if [ -f ${_inProgressFilename} ]; then
      mv "${_inProgressFilename}" "${_finalFilename}"
      echo "Backup written to ${_finalFilename} ..."
    fi
  )
}

ftpBackup(){
  (
    if [ -z "${FTP_URL}" ] ; then
      return 0
    fi    
    
    _filename=${1}
    _filenameWithExtension="${_filename}${BACKUP_FILE_EXTENSION}"
    echo "Transferring ${_filenameWithExtension} to ${FTP_URL}"    
    curl --ftp-ssl -T ${_filenameWithExtension} --user ${FTP_USER}:${FTP_PASSWORD} ${FTP_URL}
    
    if [ ${?} -eq 0 ]; then
      echo "Successfully transferred ${_filenameWithExtension} to the FTP server"
    else
      echoRed "[!!ERROR!!] - Failed to transfer ${_filenameWithExtension} with the exit code ${?}"
    fi
  )
}

listExistingBackups(){
  (
    _backupDir=${1:-${ROOT_BACKUP_DIR}}
    echoMagenta "\n================================================================================================================================"
    echoMagenta "Current Backups:"
    echoMagenta "--------------------------------------------------------------------------------------------------------------------------------"
    du -ah --time ${_backupDir}
    echoMagenta "================================================================================================================================\n"
  )
}

getNumBackupsToRetain(){
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

pruneBackups(){
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

getUsername(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostUserParam ${_hostname})
    # Backward compatibility ...
    _username="${!_paramName:-${POSTGRESQL_USER}}"
    echo ${_username}
  )
}

getPassword(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _paramName=$(getHostPasswordParam ${_hostname})
    # Backward compatibility ...
    _password="${!_paramName:-${POSTGRESQL_PASSWORD}}"
    echo ${_password}
  )
}

backupDatabase(){
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

touchBackupFile() {
  (
    # For safety, make absolutely certain the directory and file exist.
    # The pruning process removes empty directories, so if there is an error 
    # during a backup the backup directory could be deleted.
    _backupFile=${1}
    _backupDir="${_backupFile%/*}"
    makeDirectory ${_backupDir} && touch ${_backupFile}
  )
}

restoreDatabase(){
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

isLastDayOfMonth(){
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

isLastDayOfWeek(){
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

getBackupType(){
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

createBackupFolder(){
  (
    _backupTypeDir="$(getBackupType)"
    if [ ! -z "${_backupTypeDir}" ]; then
      _backupTypeDir=${_backupTypeDir}/
    fi

    _backupDir="${ROOT_BACKUP_DIR}${_backupTypeDir}`date +\%Y-\%m-\%d`/"

    # Don't actually create the folder if we're just printing the configuation.
    if [ -z "${PRINT_CONFIG}" ]; then
      echo "Making backup directory ${_backupDir} ..." >&2
      if ! makeDirectory ${_backupDir}; then
        echo $(echoRed "[!!ERROR!!] - Failed to create backup directory ${_backupDir}.") >&2
        exit 1;
      fi;
    fi

    echo ${_backupDir}
  )
}

generateFilename(){
  (
    _backupDir=${1}
    _databaseSpec=${2}
    _coreFilename=$(generateCoreFilename ${_databaseSpec})
    _filename="${_backupDir}${_coreFilename}_`date +\%Y-\%m-\%d_%H-%M-%S`"
    echo ${_filename}
  )
}

generateCoreFilename(){
  (
    _databaseSpec=${1}
    _hostname=$(getHostname ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
    _coreFilename="${_hostname}-${_database}"
    echo ${_coreFilename}
  )
}

rollingStrategy(){
  if [[ "${BACKUP_STRATEGY}" == "rolling" ]] && (( "${WEEKLY_BACKUPS}" > 0 )) && (( "${MONTHLY_BACKUPS}" >= 0 )); then
    return 0
  else
    return 1
  fi
}

dailyStrategy(){
  if [[ "${BACKUP_STRATEGY}" == "daily" ]] || (( "${WEEKLY_BACKUPS}" <= 0 )); then
    return 0
  else
    return 1
  fi
}

listSettings(){
  _backupDirectory=${1}
  _databaseList=${2}
  echo -e \\n"Settings:"
  if runOnce; then
    echo "- Run mode: Once"
  else
    echo "- Run mode: Continuous"
  fi
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
  echo "- Databases:"
  for _db in ${_databaseList}; do
    echo "  - ${_db}"
  done
  if [ -z "${FTP_URL}" ]; then
    echo "- FTP: not configured"
  else
    echo "- FTP: ${FTP_URL}"
  fi

  if [ ! -z "${_configurationError}" ]; then
    echoRed "\nConfiguration error!  The script will exit."
    sleep 5
    exit 1
  fi
  echo
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
# ======================================================================================

# =================================================================================================================
# Initialization:
# -----------------------------------------------------------------------------------------------------------------
while getopts clr:f:1h FLAG; do
  case $FLAG in
    c)
      export PRINT_CONFIG=1
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
# If we are in restore mode, restore the database and exit.
if [ ! -z "${_restoreDatabase}" ]; then
  restoreDatabase "${_restoreDatabase}" "${_fromBackup}"
  exit 0
fi

# Otherwise enter backup mode.
while true; do
  if [ -z "${PRINT_CONFIG}" ]; then
    echoBlue "\nStarting backup process ..."
  else
    echoBlue "\nListing configuration settings ..."
  fi

  databases=$(readConf)
  backupDir=$(createBackupFolder)
  listSettings "${backupDir}" "${databases}"

  if [ ! -z "${PRINT_CONFIG}" ]; then
    exit 0
  fi

  for database in ${databases}; do
    filename=$(generateFilename "${backupDir}" "${database}")
    if backupDatabase "${database}" "${filename}"; then
      finalizeBackup "${filename}"
      ftpBackup "${filename}"
      pruneBackups "${backupDir}" "${database}"
    else
      echoRed "[!!ERROR!!] - Failed to backup ${database}."
    fi
  done

  listExistingBackups ${ROOT_BACKUP_DIR}

  if runOnce; then
    echoGreen "Single backup run complete.\n"
    exit 0
  fi

  echoYellow "Sleeping for ${BACKUP_PERIOD} ...\n"
  sleep ${BACKUP_PERIOD}
done
# =================================================================================================================
