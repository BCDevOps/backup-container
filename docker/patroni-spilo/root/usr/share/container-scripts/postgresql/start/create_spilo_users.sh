#!/bin/bash

_psql () { psql --set ON_ERROR_STOP=1 "$@" ; }

echo "CREATING Spilo users admin and robot_zmon"

_psql \
<<'EOF'
CREATE USER admin;
CREATE USER robot_zmon;
EOF
