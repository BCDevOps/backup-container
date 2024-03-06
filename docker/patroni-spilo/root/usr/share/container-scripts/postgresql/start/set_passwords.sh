#!/bin/bash

_psql () { psql --set ON_ERROR_STOP=1 "$@" ; }

if [ -v POSTGRESQL_MASTER_USER ]; then
_psql --set=masteruser="$POSTGRESQL_MASTER_USER" \
      --set=masterpass="$POSTGRESQL_MASTER_PASSWORD" \
<<'EOF'
ALTER USER :"masteruser" WITH REPLICATION;
ALTER USER :"masteruser" WITH ENCRYPTED PASSWORD :'masterpass';
EOF
fi

if [ -v POSTGRESQL_ADMIN_PASSWORD ]; then
_psql --set=adminpass="$POSTGRESQL_ADMIN_PASSWORD" \
<<<"ALTER USER \"postgres\" WITH ENCRYPTED PASSWORD :'adminpass';"
fi

#_psql <<<"CREATE EXTENSION IF NOT EXISTS \"citus\";"
