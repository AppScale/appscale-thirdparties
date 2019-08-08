#!/usr/bin/env bash
# init-foundationdb.sh script ensures that FoundationDB server
# is installed and configured on the machine.

set -e
set -u

############################
### Arguments processing ###
############################

usage() {
    echo "Usage: ${0} \\"
    echo "         --cluster-file-content <STR> --host-to-listen-on <HOST> \\"
    echo "         [--server-processes-num <NUM>] [--data-dir <PATH>] \\"
    echo "         [--fdbcli-command <COMMAND>]"
    echo
    echo "Options:"
    echo "   --cluster-file-content <STR>  fdb.cluster file content."
    echo "   --host-to-listen-on <HOST>    Host name or IP to listen on."
    echo "   --server-processes-num <NUM>  Number of server processes to start "
    echo "                                 (it shouldn't be greater than number of CPUs, default: 2)."
    echo "   --data-dir <PATH>             FDB data dir path (default: /var/lib/foundationdb/data/)."
    echo "   --fdbcli-command <COMMAND>    fdbcli command to execute after cluster initialization."
    exit 1
}

CLUSTER_FILE_CONTENT=
HOST_TO_LISTEN_ON=
SERVER_PROCESSES_NUM=2
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
    if [ "${1}" = "--server-processes-num" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        SERVER_PROCESSES_NUM="${1}"
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


########################
### Helper functions ###
########################

APT_CACHE='/var/cache/apt/archives'
PACKAGE_MIRROR='http://s3.amazonaws.com/appscale-build'

log() {
    local LEVEL=${2:-INFO}
    echo "$(date +'%Y-%m-%d %T') $LEVEL $1"
}

cachepackage() {
    cached_file="${APT_CACHE}/$1"
    remote_file="${PACKAGE_MIRROR}/$1"
    expected_md5="$2"
    mkdir -p ${APT_CACHE}
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


#####################################
### Actual installation procedure ###
#####################################

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"


### Installing FDB clients package ###
#------------------------------------#
FDB_CLIENTS_PKG='foundationdb-clients_6.1.8-1_amd64.deb'
FDB_CLIENTS_MD5='f701c23c144cdee2a2bf68647f0e108e'
log "Making sure ${FDB_CLIENTS_PKG} is in ${APT_CACHE}"
cachepackage "${FDB_CLIENTS_PKG}" "${FDB_CLIENTS_MD5}"

log "Installing ${FDB_CLIENTS_PKG}"
dpkg --install ${APT_CACHE}/foundationdb-clients_6.1.8-1_amd64.deb


### Installing FDB server package ###
#-----------------------------------#
FDB_SERVER_PKG='foundationdb-server_6.1.8-1_amd64.deb'
FDB_SERVER_MD5='80a427be14a329d864a91c9ce464d73c'
log "Making sure ${FDB_SERVER_PKG} is in ${APT_CACHE}"
cachepackage "${FDB_SERVER_PKG}" "${FDB_SERVER_MD5}"

log "Installing ${FDB_SERVER_PKG}"
dpkg --install ${APT_CACHE}/foundationdb-server_6.1.8-1_amd64.deb


### Getting rid of init.d management ###
#--------------------------------------#
log 'Making sure init.d does not manage FoundationDB'
/etc/init.d/foundationdb stop
update-rc.d foundationdb disable
# rm /etc/init.d/foundationdb


### Ensuring FDB directories are accessible ###
#---------------------------------------------#
log 'Making sure FDB directories are created and are owned by foundationdb user.'
mkdir -pv /var/run/foundationdb
chown foundationdb:foundationdb /var/run/foundationdb
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
echo "${CLUSTER_FILE_CONTENT}" > /etc/foundationdb/fdb.cluster


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
  for server_id in $(seq 4500 $((4500 + SERVER_PROCESSES_NUM - 1))); do
    echo "[fdbserver.${server_id}]"
  done
)
envsubst '$HOST_TO_LISTEN_ON $DATA_DIR $FDB_SERVERS'\
 < "${SCRIPT_DIR}/foundationdb.conf" > "${CONF_FILE}"


### Defining systemd service ###
#------------------------------#
log 'Configuring systemd to manage FoundationDB'
UNIT_FILE=/etc/systemd/system/foundationdb.service
log "Filling ${UNIT_FILE} file"
if [ -f "${UNIT_FILE}" ]; then
  cp ${UNIT_FILE} "${UNIT_FILE}.$(date +'%Y-%m-%d_%H-%M-%S')"
fi
# Give FDB processes at most half of total memory (kill if greater).
TOTAL_MEM_KB=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
FDB_MEM_MAX=$(echo "$TOTAL_MEM_KB" | awk '{ printf "%d", $1 * 0.9 / 1024 }')
DATA_DIRS=''
for server_id in $(seq 4500 $((4500 + SERVER_PROCESSES_NUM - 1))); do
  DATA_DIRS="${DATA_DIRS}${DATA_DIR}/${server_id} "
done
export MEMORY_MAX="${FDB_MEM_MAX}M"
export DATA_DIRS
envsubst '$DATA_DIRS $SERVER_PROCESSES_NUM $MEMORY_MAX'\
 < "${SCRIPT_DIR}/foundationdb.service" > "${UNIT_FILE}"

systemctl daemon-reload
systemctl enable foundationdb.service
systemctl restart foundationdb.service
systemctl status foundationdb.service

if [ ! -z "${FDBCLI_COMMAND}" ]; then
  log "Running fdbcli command: \`${FDBCLI_COMMAND}\`"
  fdbcli --exec "${FDBCLI_COMMAND}"
fi
