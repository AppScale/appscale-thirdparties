#!/usr/bin/env bash
# Downloads foundationdb deb packages to appscale cache.

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"

source "$(dirname ${SCRIPT_DIR})/common.sh"

FDB_CLIENTS_PKG='foundationdb-clients_6.1.8-1_amd64.deb'
FDB_CLIENTS_MD5='f701c23c144cdee2a2bf68647f0e108e'
log "Making sure ${FDB_CLIENTS_PKG} is in appscale cache"
cachepackage "${FDB_CLIENTS_PKG}" "${FDB_CLIENTS_MD5}"

FDB_SERVER_PKG='foundationdb-server_6.1.8-1_amd64.deb'
FDB_SERVER_MD5='80a427be14a329d864a91c9ce464d73c'
log "Making sure ${FDB_SERVER_PKG} is in appscale cache"
cachepackage "${FDB_SERVER_PKG}" "${FDB_SERVER_MD5}"
