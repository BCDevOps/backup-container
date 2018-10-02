#!/bin/bash
# Postgresql automated backup script
# See README.md for documentation on this script

# ======================================================================================
# Funtions:
# --------------------------------------------------------------------------------------
echoError (){
  _msg=${1}
  _red='\033[0;31m'
  _nc='\033[0m' # No Color
  echo -e "${_red}${_msg}${_nc}"
}

echoWarning (){
  _msg=${1}
  _yellow='\033[1;33m'
  _nc='\033[0m' # No Color
  echo -e "${_yellow}${_msg}${_nc}"
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
    else
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
    _backupDir=${1}
    echo -e \\n"================================================================================================================================"
    echoWarning "Current Backups:"
    echo -e "--------------------------------------------------------------------------------------------------------------------------------"
    du -ah --time ${_backupDir}
    echo -e "================================================================================================================================"\\n
  )
}

pruneBackups(){
  (
    _backupDir=${1:-${BACKUP_DIR}}
    _count=${2:-${NUM_BACKUPS}}
    find ${_backupDir}* | grep gz | sort -r | sed "1,${_count}d" | xargs rm -rf
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
    
    echoWarning "\nBacking up ${_databaseSpec} ..."

    export PGPASSWORD=${_password}
    touch "${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}"
    if pg_dump -Fp -h "${_hostname}" -p "${_port}" -U "${_username}" "${_database}" | gzip > ${_fileName}${IN_PROGRESS_BACKUP_FILE_EXTENSION}; then
      return 0
    else
      return 1
    fi
  )
}

createBackupFolder(){
  (
    _backupDir=${BACKUP_DIR}"`date +\%Y-\%m-\%d`/"
    echo "Making backup directory ${_backupDir} ..." >&2
    if ! mkdir -p ${_backupDir}; then
      echo "Failed to create backup directory ${_backupDir}." >&2
      exit 1;
    fi;
    echo ${_backupDir}
  )
}

generateFilename(){
  (
    _backupDir=${1}
    _databaseSpec=${2}
    _hostname=$(getHostname ${_databaseSpec})
    _database=$(getDatabaseName ${_databaseSpec})
    _filename="${_backupDir}${_hostname}-${_database}_`date +\%Y-\%m-\%d-%H-%M`"
    echo ${_filename}
  )
}
# ======================================================================================

# ======================================================================================
# Set Defaults
# --------------------------------------------------------------------------------------
export BACKUP_FILE_EXTENSION=".sql.gz"
export IN_PROGRESS_BACKUP_FILE_EXTENSION=".sql.gz.in_progress"

export DEFAULT_PORT=${POSTGRESQL_PORT_NUM:-5432}
export NUM_BACKUPS=${NUM_BACKUPS:-31}
export BACKUP_PERIOD=${BACKUP_PERIOD:-1d}
export BACKUP_CONF=${BACKUP_CONF:-backup.conf}

export BACKUP_DIR=${BACKUP_DIR:-/backups/}
# ======================================================================================

# ======================================================================================
# Main Script
# --------------------------------------------------------------------------------------
while true; do
  echo "Starting backup process ..."
  databases=$(readConf)
  backupDir=$(createBackupFolder)
  for database in ${databases}; do
    filename=$(generateFilename "${backupDir}" "${database}")
    if backupDatabase "${database}" "${filename}"; then
      finalizeBackup "${filename}"
      pruneBackups
    else
      echoError "\n[!!ERROR!!] Failed to backup ${database}.\n"
    fi
  done

  listExistingBackups ${backupDir}

  echo -e "Sleeping for ${BACKUP_PERIOD} ..."\\n
  sleep ${BACKUP_PERIOD}
done
# ======================================================================================
