#!/usr/bin/env bash
#
# Ensures that Postgres is installed on this machine.
# Creates DB and user.
# Configures Postgres to accept host connections to new Database.

set -eu

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"
source "$(dirname ${SCRIPT_DIR})/common.sh"

############################
### Arguments processing ###
############################

usage() {
    echo "Usage: ${0} --host <HOST> --dbname <DBNAME> --username <USERNAME> \\"
    echo "            --password <USER_PWD>"
    echo
    echo "Options:"
    echo "   --host <HOST>          Host IP to accept connections on"
    echo "   --dbname <DBNAME>      Database name to create"
    echo "   --username <USERNAME>  Role name to create"
    echo "   --password <USER_PWD>  Password to use for new user"
    exit 1
}

HOST=
DBNAME=
USERNAME=
PASSWORD=

# Let's get the command line arguments.
while [ $# -gt 0 ]; do
    if [ "${1}" = "--host" ]; then
        shift; if [ -z "${1:-}" ]; then usage; fi
        HOST="${1}"
        shift; continue
    fi
    if [ "${1}" = "--dbname" ]; then
        shift; if [ -z "${1:-}" ]; then usage; fi
        DBNAME="${1}"
        shift; continue
    fi
    if [ "${1}" = "--username" ]; then
        shift; if [ -z "${1:-}" ]; then usage; fi
        USERNAME="${1}"
        shift; continue
    fi
    if [ "${1}" = "--password" ]; then
        shift; if [ -z "${1:-}" ]; then usage; fi
        PASSWORD="${1}"
        shift; continue
    fi
    echo -e "\nParameter '${1}' is not recognized\n"
    usage
done

if [ -z "${HOST}" ] || [ -z "${DBNAME}" ] || [ -z "${USERNAME}" ] || [ -z "${PASSWORD}" ]; then
    usage
fi


#####################################
### Actual installation procedure ###
#####################################

${SCRIPT_DIR}/install.sh

log "Updating Postgres configs to accept host connections to the Database"
PG_MAJOR_VER=$(psql --version | awk '{ print $3 }' | awk -F '.' '{ print $1 }')
PG_VERSION=$(psql --version | awk '{ print $3 }' | awk -F '.' '{ print $1 "." $2 }')

if (( "${PG_MAJOR_VER}" >= 10 )); then
    PG_CONFIG_DIR="/etc/postgresql/${PG_MAJOR_VER}"
else
    PG_CONFIG_DIR="/etc/postgresql/${PG_VERSION}"
fi

PG_CONF="${PG_CONFIG_DIR}/main/postgresql.conf"
PG_HBA="${PG_CONFIG_DIR}/main/pg_hba.conf"

# Configure postgres to listen on the specified host
if grep -q -E "^listen_addresses *=" "${PG_CONF}"
then
    sed -i "s/^listen_addresses *=.*/listen_addresses = 'localhost,${HOST}'/" "${PG_CONF}"
else
    echo "listen_addresses = 'localhost,${HOST}'" >> "${PG_CONF}"
fi

# Allow host connections to the specified DB
if grep -q -E "^host[ \t]+${DBNAME}[ \t]+${USERNAME}[ \t]+" "${PG_HBA}"
then
    sed -i "s|^host[ \t]+${DBNAME}[ \t]+${USERNAME}[ \t]+.*|host ${DBNAME} ${USERNAME} 0.0.0.0/0 md5|" "${PG_HBA}"
else
    echo "host ${DBNAME} ${USERNAME} 0.0.0.0/0 md5" >> "${PG_HBA}"
fi

systemctl restart postgresql.service
systemctl enable postgresql.service
systemctl status postgresql.service


echo "${HOST}:5432:${DBNAME}:${USERNAME}:${PASSWORD}" > ~/.pgpass
chmod 600 ~/.pgpass

log "Checking if DB and user already exist"
if psql --dbname ${DBNAME} --username ${USERNAME} --host ${HOST} \
        --command 'SELECT current_timestamp;'
then
    rm ~/.pgpass
    log "DB and user are already configured"
    exit 0
else
    rm ~/.pgpass
fi


log "Creating Database and Role"
CREATE_ROLE="CREATE ROLE \"${USERNAME}\" WITH LOGIN PASSWORD '${PASSWORD}';"
sudo -u postgres psql --command "${CREATE_ROLE}"
sudo -u postgres createdb --owner "${USERNAME}" "${DBNAME}"
