# ========================================================================
# Special Deployment Parameters needed for the backup instance.
# ------------------------------------------------------------------------
# The generated config map is used to update the Backup configuration.
# ========================================================================

CONFIG_MAP_NAME=backup-conf
SOURCE_FILE=../config/backup.conf
OUTPUT_FORMAT=json
OUTPUT_FILE=backup-conf-configmap_DeploymentConfig.json

generateConfigMap() {  
  _config_map_name=${1}
  _source_file=${2}
  _output_format=${3}
  _output_file=${4}
  if [ -z "${_config_map_name}" ] || [ -z "${_source_file}" ] || [ -z "${_output_format}" ] || [ -z "${_output_file}" ]; then
    echo -e \\n"generateConfigMap; Missing parameter!"\\n
    exit 1
  fi

  oc create configmap ${_config_map_name} --from-file ${_source_file} --dry-run -o ${_output_format} > ${_output_file}
}

printStatusMsg(){
  (
    _msg=${1}
    _yellow='\033[1;33m'
    _nc='\033[0m' # No Color
    printf "\n${_yellow}${_msg}\n${_nc}" >&2
  )
}

readParameter(){
  (
    _msg=${1}
    _paramName=${2}
    _defaultValue=${3}
    _encode=${4}

    _yellow='\033[1;33m'
    _nc='\033[0m' # No Color
    _message=$(echo -e "\n${_yellow}${_msg}\n${_nc}")

    read -r -p $"${_message}" ${_paramName}

    writeParameter "${_paramName}" "${_defaultValue}" "${_encode}"
  )
}

writeParameter(){
  (
    _paramName=${1}
    _defaultValue=${2}
    _encode=${3}

    if [ -z "${_encode}" ]; then
      echo "${_paramName}=${!_paramName:-${_defaultValue}}" >> ${_overrideParamFile}
    else
      # The key/value pair must be contained on a single line
      _encodedValue=$(echo -n "${!_paramName:-${_defaultValue}}"|base64 -w 0)
      echo "${_paramName}=${_encodedValue}" >> ${_overrideParamFile}
    fi
  )
}

initialize(){
  # Define the name of the override param file.
  _scriptName=$(basename ${0%.*})
  export _overrideParamFile=${_scriptName}.param

  printStatusMsg "Initializing ${_scriptName} ..."

  # Remove any previous version of the file ...
  if [ -f ${_overrideParamFile} ]; then
    printStatusMsg "Removing previous copy of ${_overrideParamFile} ..."
    rm -f ${_overrideParamFile}
  fi
}

initialize

generateConfigMap "${CONFIG_MAP_NAME}" "${SOURCE_FILE}" "${OUTPUT_FORMAT}" "${OUTPUT_FILE}"

# Get the FTP URL and credentials
readParameter "FTP_URL - Please provide the FTP server URL.  If left blank, the FTP backup feature will be disabled:" FTP_URL "" 
readParameter "FTP_USER - Please provide the FTP user name:" FTP_USER "" 
readParameter "FTP_PASSWORD - Please provide the FTP password:" FTP_PASSWORD "" 

# Get the webhook URL
readParameter "WEBHOOK_URL - Please provide the webhook endpoint URL.  If left blank, the webhook integration feature will be disabled:" WEBHOOK_URL "" 

SPECIALDEPLOYPARMS="--param-file=${_overrideParamFile}"
echo ${SPECIALDEPLOYPARMS}

