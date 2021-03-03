#!/bin/bash
_includeFile=$(type -p overrides.inc)
# Import ocFunctions.inc for getSecret
_ocFunctions=$(type -p ocFunctions.inc)
if [ ! -z ${_includeFile} ]; then
  . ${_ocFunctions}
  . ${_includeFile}
else
  _red='\033[0;31m'; _yellow='\033[1;33m'; _nc='\033[0m'; echo -e \\n"${_red}overrides.inc could not be found on the path.${_nc}\n${_yellow}Please ensure the openshift-developer-tools are installed on and registered on your path.${_nc}\n${_yellow}https://github.com/BCDevOps/openshift-developer-tools${_nc}"; exit 1;
fi

# ========================================================================
# Special Deployment Parameters needed for the backup instance.
# ------------------------------------------------------------------------
# The generated config map is used to update the Backup configuration.
# ========================================================================
CONFIG_MAP_NAME=${CONFIG_MAP_NAME:-backup-conf}
SOURCE_FILE=../config/backup.conf

OUTPUT_FORMAT=json
OUTPUT_FILE=${CONFIG_MAP_NAME}-configmap_DeploymentConfig.json

printStatusMsg "Generating ConfigMap; ${CONFIG_MAP_NAME} ..."
generateConfigMap "${CONFIG_MAP_NAME}" "${SOURCE_FILE}" "${OUTPUT_FORMAT}" "${OUTPUT_FILE}"


if createOperation; then
  # Get the FTP URL and credentials
  readParameter "FTP_URL - Please provide the FTP server URL.  If left blank, the FTP backup feature will be disabled:" FTP_URL "false"
  parseHostnameParameter "FTP_URL" "FTP_URL_HOST"
  readParameter "FTP_USER - Please provide the FTP user name:" FTP_USER ""
  readParameter "FTP_PASSWORD - Please provide the FTP password:" FTP_PASSWORD ""

  # Get the webhook URL
  readParameter "WEBHOOK_URL - Please provide the webhook endpoint URL.  If left blank, the webhook integration feature will be disabled:" WEBHOOK_URL "false"
  parseHostnameParameter "WEBHOOK_URL" "WEBHOOK_URL_HOST"
else
  printStatusMsg "Update operation detected ...\nSkipping the prompts for the FTP_URL, FTP_USER, FTP_PASSWORD, and WEBHOOK_URL secrets ...\n"
  writeParameter "FTP_URL" "prompt_skipped"
  writeParameter "FTP_USER" "prompt_skipped"
  writeParameter "FTP_PASSWORD" "prompt_skipped"
  writeParameter "WEBHOOK_URL" "prompt_skipped"

  # Get FTP_URL_HOST from secret
  printStatusMsg "Getting FTP_URL_HOST for the ExternalNetwork definition from secret ...\n"
  writeParameter "FTP_URL_HOST" $(getSecret "${FTP_SECRET_KEY}" "ftp-url-host") "false"

  # Get WEBHOOK_URL_HOST from secret
  printStatusMsg "Getting WEBHOOK_URL_HOST for the ExternalNetwork definition from secret ...\n"
  writeParameter "WEBHOOK_URL_HOST" $(getSecret "${NAME}" "webhook-url-host") "false"
fi

SPECIALDEPLOYPARMS="--param-file=${_overrideParamFile}"
echo ${SPECIALDEPLOYPARMS}

