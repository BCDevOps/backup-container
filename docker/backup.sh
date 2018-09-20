#!/bin/bash
# Postgresql automated backup script
# See README.md for documentation on this script

export NUM_BACKUPS="${NUM_BACKUPS:-31}"
export BACKUP_PERIOD="${BACKUP_PERIOD:-1d}"

while true; do
  FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`/"
  DBFILE=$FINAL_BACKUP_DIR"$POSTGRESQL_DATABASE`date +\%Y-\%m-\%d-%H-%M`"
  echo "Making backup directory in $FINAL_BACKUP_DIR"
  
  if ! mkdir -p $FINAL_BACKUP_DIR; then
    echo "Cannot create backup directory in $FINAL_BACKUP_DIR." 1>&2
    exit 1;
  fi;

  export PGPASSWORD=$POSTGRESQL_PASSWORD



  if ! pg_dump -Fp -h "$DATABASE_SERVICE_NAME" -U "$POSTGRESQL_USER" "$POSTGRESQL_DATABASE" | gzip > $DBFILE.sql.gz.in_progress; then
    echo "[!!ERROR!!] Failed to backup database $POSTGRESQL_DATABASE" 
  else
    mv $DBFILE.sql.gz.in_progress $DBFILE.sql.gz
    echo "Database backup written to $DBFILE.sql.gz"
    
    # cull backups to a limit of NUM_BACKUPS
    find ${BACKUP_DIR}* | grep gz | sort -r | sed "1,${NUM_BACKUPS}d" | xargs rm -rf
  fi;
  echo "Current Backups:"
  ls -alh ${BACKUP_DIR}/*/*sql.gz*
  echo "===================="

  # 24 hrs
  sleep ${BACKUP_PERIOD}

done