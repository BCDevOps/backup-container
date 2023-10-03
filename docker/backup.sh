#!/bin/bash

# ======================================================================================
# Imports
# --------------------------------------------------------------------------------------
. ./backup.usage                # Usage information
. ./backup.logging              # Logging functions
. ./backup.config.utils         # Configuration functions
. ./backup.container.utils      # Container Utility Functions
. ./backup.s3                   # S3 Support functions
. ./backup.ftp                  # FTP Support functions
. ./backup.misc.utils           # General Utility Functions
. ./backup.file.utils           # File Utility Functions
. ./backup.utils                # Primary Database Backup and Restore Functions
. ./backup.server.utils         # Backup Server Utility Functions
. ./backup.settings             # Default Settings
# ======================================================================================

# ======================================================================================
# Initialization:
# --------------------------------------------------------------------------------------
trap shutDown EXIT TERM

# Load database plug-in based on the container type ...
. ./backup.${CONTAINER_TYPE}.plugin > /dev/null 2>&1
if [[ ${?} != 0 ]]; then
  echoRed "backup.${CONTAINER_TYPE}.plugin not found."
  
  # Default to null plugin.
  export CONTAINER_TYPE=${UNKNOWN_DB}
  . ./backup.${CONTAINER_TYPE}.plugin > /dev/null 2>&1
fi

while getopts nclr:v:f:1spha:I FLAG; do
  case $FLAG in
    n)
      # Allow null database plugin ...
      # Without this flag loading the null plugin is considered a configuration error.
      # The null plugin can be used for testing.
      export _allowNullPlugin=1
      ;;
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
    a)
      export _adminPassword=${OPTARG}
      ;;
    I)
      export IGNORE_ERRORS=1
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
# ======================================================================================

# ======================================================================================
# Main Script
# --------------------------------------------------------------------------------------
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
    unset restoreFlags
    if isScripted; then
      restoreFlags="-q"
    fi

    if validateOperation "${_restoreDatabase}" "${RESTORE}"; then
      restoreDatabase ${restoreFlags} "${_restoreDatabase}" "${_fromBackup}"
    fi
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
# ======================================================================================
