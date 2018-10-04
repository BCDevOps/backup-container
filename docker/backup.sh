#!/bin/bash
# Postgresql automated backup script
# See README.md for documentation on this script

# ======================================================================================
# Funtions:
# --------------------------------------------------------------------------------------
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

finalizeBackup(){
  (
    _filename=${1}
    mv ${_filename}${IN_PROGRESS_BACKUP_FILE_EXTENSION} ${_filename}${BACKUP_FILE_EXTENSION}
    echo "Backup written to ${_filename}${BACKUP_FILE_EXTENSION} ..."
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
    
    echoGreen "\nBacking up ${_databaseSpec} ..."

    export PGPASSWORD=${_password}
    SECONDS=0
    touch "${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"
    if pg_dump -Fp -h "${_hostname}" -p "${_port}" -U "${_username}" "${_database}" | gzip > ${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}; then
      return 0
    else
      return 1
    fi
    duration=$SECONDS
    echo "Elapsed time: $(($duration / 3600))h:$(($duration / 60))m:$(($duration % 60))s"
  )
}

isLastDayOfMonth(){
  (
    _date=${1:-$(date)}
    _day=$(date -d "${_date}" +%d)
    _month=$(date -d "${_date}" +%m)
    _lastDayOfMonth=$(date -d "${_month}/1 + 1 month - 1 day" "+%d")

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
    _backupTypeDir="$(getBackupType)/"
    _backupDir="${ROOT_BACKUP_DIR}${_backupTypeDir}`date +\%Y-\%m-\%d`/"
    echo "Making backup directory ${_backupDir} ..." >&2
    if ! mkdir -p ${_backupDir}; then
      echo $(echoRed "[!!ERROR!!] - Failed to create backup directory ${_backupDir}.") >&2
      exit 1;
    fi;
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
  (
    _backupDir=${1}
    _databases=${2}
    echo -e \\n"Settings:"
    if rollingStrategy; then
      echo "- Backup strategy: rolling"
    fi
    if dailyStrategy; then
      echo "- Backup strategy: daily"
    fi
    backupType=$(getBackupType)
    if [ -z "${backupType}" ]; then
      echo "- Backup type: flat daily"
    else
      echo "- Backup type: ${backupType}"
    fi
    echo "- Number of each backup to retain: $(getNumBackupsToRetain)"
    echo "- Backup folder: ${_backupDir}"
    echo "- Databases:"
    for _database in ${_databases}; do
      echo "  - ${_database}"
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
# ======================================================================================

# ======================================================================================
# Main Script
# --------------------------------------------------------------------------------------
while true; do
  echoBlue "\nStarting backup process ..."
  databases=$(readConf)
  backupDir=$(createBackupFolder)
  listSettings "${backupDir}" "${databases}"

  for database in ${databases}; do
    filename=$(generateFilename "${backupDir}" "${database}")
    if backupDatabase "${database}" "${filename}"; then
      finalizeBackup "${filename}"
      pruneBackups "${backupDir}" "${database}"
    else
      echoRed "\n[!!ERROR!!] - Failed to backup ${database}.\n"
    fi
  done

  listExistingBackups ${ROOT_BACKUP_DIR}

  echoYellow "Sleeping for ${BACKUP_PERIOD} ...\n"
  sleep ${BACKUP_PERIOD}
done
# ======================================================================================
