#!/bin/bash

_psql () { psql --set ON_ERROR_STOP=1 "$@" ; }

echo "CREATING $POSTGRESQL_USER"

_psql --set=db="$POSTGRESQL_DATABASE" \
 --set=user="$POSTGRESQL_USER" \
 --set=pass="$POSTGRESQL_PASSWORD" \
<<'EOF'
CREATE DATABASE :"db";
CREATE USER :"user" PASSWORD :'pass';
EOF
