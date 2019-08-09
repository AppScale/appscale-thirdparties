#!/usr/bin/env bash
# init-foundationdb.sh script ensures that FoundationDB server
# is installed and configured on the machine.

set -eu


########################
### Helper functions ###
########################

PACKAGE_CACHE='/var/cache/appscale'
PACKAGE_MIRROR='http://s3.amazonaws.com/appscale-build'

log() {
    local LEVEL=${2:-INFO}
    echo "$(date +'%Y-%m-%d %T') $LEVEL $1"
}

cachepackage() {
    cached_file="${PACKAGE_CACHE}/$1"
    remote_file="${PACKAGE_MIRROR}/$1"
    expected_md5="$2"
    mkdir -p ${PACKAGE_CACHE}
    if [ -f ${cached_file} ]; then
        md5=($(md5sum ${cached_file}))
        if [ "$md5" = "$2" ]; then
            return 0
        else
            log "Incorrect md5sum for ${cached_file}. Removing it." "ERROR"
            rm ${cached_file}
        fi
    fi

    log "Fetching ${remote_file}"
    if ! curl -fs "${remote_file}" > "${cached_file}"; then
        log "Error while downloading ${remote_file}" "ERROR"
        return 1
    fi

    actual_md5=($(md5sum ${cached_file}))
    if [ "${actual_md5}" = "${expected_md5}" ]; then
        return 0
    else
        log "md5 sum of downloaded file is ${actual_md5} though ${expected_md5} was expected" "ERROR"
        log "Try downloading package manually to ${cached_file} and running script again"
        rm ${cached_file}
        return 1
    fi
}

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

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"

mkdir -p "${PACKAGE_CACHE}"


### Installing FDB clients package ###
#------------------------------------#
FDB_CLIENTS_PKG='foundationdb-clients_6.1.8-1_amd64.deb'
FDB_CLIENTS_MD5='f701c23c144cdee2a2bf68647f0e108e'
log "Making sure ${FDB_CLIENTS_PKG} is in ${PACKAGE_CACHE}"
cachepackage "${FDB_CLIENTS_PKG}" "${FDB_CLIENTS_MD5}"

log "Installing ${FDB_CLIENTS_PKG}"
dpkg --install ${PACKAGE_CACHE}/foundationdb-clients_6.1.8-1_amd64.deb


### Installing FDB server package ###
#-----------------------------------#
FDB_SERVER_PKG='foundationdb-server_6.1.8-1_amd64.deb'
FDB_SERVER_MD5='80a427be14a329d864a91c9ce464d73c'
log "Making sure ${FDB_SERVER_PKG} is in ${PACKAGE_CACHE}"
cachepackage "${FDB_SERVER_PKG}" "${FDB_SERVER_MD5}"

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
