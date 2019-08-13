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
    echo "Usage: ${0} \\"
    echo "         --cluster-file-content <STR> --host-to-listen-on <HOST> \\"
    echo "         [--data-dir <PATH>] [--fdbcli-command <COMMAND>]"
    echo
    echo "Options:"
    echo "   --cluster-file-content <STR>  fdb.cluster file content."
    echo "   --host-to-listen-on <HOST>    Host name or IP to listen on."
    echo "   --data-dir <PATH>             FDB data dir path (default: /var/lib/foundationdb/data/)."
    echo "   --fdbcli-command <COMMAND>    fdbcli command to execute after cluster initialization."
    exit 1
}

CLUSTER_FILE_CONTENT=
HOST_TO_LISTEN_ON=
DATA_DIR=/var/lib/foundationdb/data/
FDBCLI_COMMAND=

# Let's get the command line arguments.
while [ $# -gt 0 ]; do
    if [ "${1}" = "--cluster-file-content" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        CLUSTER_FILE_CONTENT="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--host-to-listen-on" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        HOST_TO_LISTEN_ON="${1}"
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

if [ -z "${CLUSTER_FILE_CONTENT}" ] || [ -z "${HOST_TO_LISTEN_ON}" ]; then
    usage
fi

CLUSTER_SERVERS=$(echo "${CLUSTER_FILE_CONTENT}" | awk -F '@' '{ print $2 }' | tr '\r\n' ' ' | sed 's/,/ /g' )
HOST_SERVER_IDS=
for server_address in ${CLUSTER_SERVERS} ; do
  host=$(echo "${server_address}" | awk -F ':' '{ print $1 }')
  port=$(echo "${server_address}" | awk -F ':' '{ print $2 }')
  if [ "${host}" = "${HOST_TO_LISTEN_ON}" ] ; then
    HOST_SERVER_IDS+="${port} "
  fi
done

if [ -z "${HOST_SERVER_IDS}" ] ; then
  log "Cluster file doesn't declare any servers for a current host (${HOST_TO_LISTEN_ON})"
  log 'No FDB servers will be started on the current host' 'WARNING'
fi


#####################################
### Actual installation procedure ###
#####################################


### Installing FDB clients package ###
#------------------------------------#
${SCRIPT_DIR}/download_artifacts.sh
FDB_CLIENTS_PKG='foundationdb-clients_6.1.8-1_amd64.deb'
FDB_SERVER_PKG='foundationdb-server_6.1.8-1_amd64.deb'

log "Installing ${FDB_CLIENTS_PKG}"
dpkg --install ${PACKAGE_CACHE}/foundationdb-clients_6.1.8-1_amd64.deb

log "Installing ${FDB_SERVER_PKG}"
dpkg --install ${PACKAGE_CACHE}/foundationdb-server_6.1.8-1_amd64.deb


### Ensuring FDB directories are accessible ###
#---------------------------------------------#
log 'Making sure FDB directories are created and are owned by foundationdb user.'
mkdir -pv /var/log/foundationdb
chown -R foundationdb:foundationdb /var/log/foundationdb
mkdir -pv "${DATA_DIR}"
chown -R foundationdb:foundationdb "${DATA_DIR}"


### Filling /etc/foundationdb/fdb.cluster ###
#-------------------------------------------#
CLUSTER_FILE=/etc/foundationdb/fdb.cluster
log "Filling ${CLUSTER_FILE} file"
if [ -f "${CLUSTER_FILE}" ]; then
  cp ${CLUSTER_FILE} "${CLUSTER_FILE}.$(date +'%Y-%m-%d_%H-%M-%S')"
fi
echo "${CLUSTER_FILE_CONTENT}" > "${CLUSTER_FILE}"


### Filling /etc/foundationdb/foundationdb.conf ###
#-------------------------------------------------#
CONF_FILE=/etc/foundationdb/foundationdb.conf
log "Filling ${CONF_FILE} file"
if [ -f "${CONF_FILE}" ]; then
  cp ${CONF_FILE} "${CONF_FILE}.$(date +'%Y-%m-%d_%H-%M-%S')"
fi
export HOST_TO_LISTEN_ON
export DATA_DIR
export FDB_SERVERS=$(
  for server_id in ${HOST_SERVER_IDS}; do
    echo "[fdbserver.${server_id}]"
  done
)
envsubst '$HOST_TO_LISTEN_ON $DATA_DIR $FDB_SERVERS'\
 < "${SCRIPT_DIR}/foundationdb.conf" > "${CONF_FILE}"


systemctl enable foundationdb.service
systemctl start foundationdb.service
systemctl status foundationdb.service


log 'Waiting for FDB cluster to start'
wait_start=$(date +%s)
while ! fdbcli --exec status
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
