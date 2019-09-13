#!/usr/bin/env bash
# init-foundationdb.sh script ensures that FoundationDB server
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
${SCRIPT_DIR}/install.sh

if [ -n "${DATA_DIR}" ]; then
    mkdir -pv "${DATA_DIR}"
    chown -R foundationdb:foundationdb "${DATA_DIR}"
    PATTERN="^[# ]*datadir *=.*$"
    NEW_CONFIG_LINE="datadir = ${DATA_DIR}/\$ID"
    sed -i "s%${PATTERN}%${NEW_CONFIG_LINE}%" /etc/foundationdb/foundationdb.conf
fi

if [ -n "${PUBLIC_ADDRESS}" ]; then
    apt install python
    python /usr/lib/foundationdb/make_public.py -a ${PUBLIC_ADDRESS}
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

log 'Waiting for FDB cluster to start'
wait_start=$(date +%s)
while ! fdbcli --exec status | grep -IE 'Coordinators *- *[1-9]'
do
    current_time=$(date +%s)
    elapsed_time=$((current_time - wait_start))
    if [ "${elapsed_time}" -gt 60 ] ; then
        log 'Timed out waiting for FDB cluster to start' 'ERROR'
        exit 1
    fi
    sleep 5
done

if [ ! -z "${FDBCLI_COMMAND}" ]; then
  log "Running fdbcli command: \`${FDBCLI_COMMAND}\`"
  fdbcli --exec "${FDBCLI_COMMAND}"
fi
