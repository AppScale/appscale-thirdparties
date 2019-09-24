#!/usr/bin/env bash
# This script ensures that FoundationDB server
# is installed and configured on the machine.

set -eu

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"

source "$(dirname ${SCRIPT_DIR})/common.sh"

############################
### Arguments processing ###
############################

usage() {
    echo "Usage: ${0} [--public-address <HOST>] [--data-dir <PATH>] [--fdbcli-command <COMMAND>]"
    echo
    echo "Options:"
    echo "   --public-address <HOST>      Host name or IP to listen on."
    echo "   --data-dir <PATH>            FDB data dir path (default: /var/lib/foundationdb/data/)."
    echo "   --fdbcli-command <COMMAND>   fdbcli command to execute after cluster initialization."
    exit 1
}

PUBLIC_ADDRESS=
DATA_DIR=
FDBCLI_COMMAND=

# Let's get the command line arguments.
while [ $# -gt 0 ]; do
    if [ "${1}" = "--public-address" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        PUBLIC_ADDRESS="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--data-dir" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        DATA_DIR="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--fdbcli-command" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        FDBCLI_COMMAND="${1}"
        shift
        continue
    fi
    usage
done


#####################################
### Actual installation procedure ###
#####################################


### Installing FDB clients package ###
#------------------------------------#

if ! (dpkg -l foundationdb-server && dpkg -l foundationdb-clients) > /dev/null 2>&1; then
    ${SCRIPT_DIR}/install.sh
fi

if [ -n "${DATA_DIR}" ]; then
    mkdir -pv "${DATA_DIR}"
    chown -R foundationdb:foundationdb "${DATA_DIR}"
    PATTERN="^[# ]*datadir *=.*$"
    NEW_CONFIG_LINE="datadir = ${DATA_DIR}/\$ID"
    sed -i "s%${PATTERN}%${NEW_CONFIG_LINE}%" /etc/foundationdb/foundationdb.conf
fi

if [ -n "${PUBLIC_ADDRESS}" ]; then
    apt-get --assume-yes install python
    if ! python /usr/lib/foundationdb/make_public.py -a ${PUBLIC_ADDRESS}; then
        if ! grep -E "[^0-9]${PUBLIC_ADDRESS}:" /etc/foundationdb/fdb.cluster; then
            fdb_cluster=$(cat /etc/foundationdb/fdb.cluster)
            log "Can't use public address ${PUBLIC_ADDRESS} with fdb.cluster: '${fdb_cluster}'" "ERROR"
            exit 1
        fi
    fi
    PATTERN="^[# ]*public_address *=.*$"
    NEW_CONFIG_LINE="public_address = ${PUBLIC_ADDRESS}:\$ID"
    sed -i "s%${PATTERN}%${NEW_CONFIG_LINE}%" /etc/foundationdb/foundationdb.conf
fi

log 'Making sure FDB directories are created and are owned by foundationdb user.'
mkdir -pv /var/log/foundationdb
chown -R foundationdb:foundationdb /var/log/foundationdb


### Starting and enabling foundationdb.service ###
#------------------------------------------------#
systemctl start foundationdb.service
systemctl enable foundationdb.service
systemctl status foundationdb.service

if [ ! -z "${FDBCLI_COMMAND}" ]; then
  log "Running fdbcli command: \`${FDBCLI_COMMAND}\`"
  fdbcli --exec "${FDBCLI_COMMAND}"
fi
