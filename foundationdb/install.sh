#!/usr/bin/env bash
# Downloads foundationdb deb packages to appscale cache.

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"

source "$(dirname ${SCRIPT_DIR})/common.sh"

FDB_CLIENTS_PKG='foundationdb-clients_6.1.8-1_amd64.deb'
FDB_CLIENTS_SHA384='34e8d73e1b792a1906226063731d1365edcf83804a5ae63803d101375d79522f823a6b8c782efb95fda9b05bf2e5a12e'
log "Making sure ${FDB_CLIENTS_PKG} is in appscale cache"
cachepackage "${FDB_CLIENTS_PKG}" "${FDB_CLIENTS_SHA384}"

log "Installing ${FDB_CLIENTS_PKG}"
dpkg --install ${PACKAGE_CACHE}/foundationdb-clients_6.1.8-1_amd64.deb
rm ${PACKAGE_CACHE}/foundationdb-clients_6.1.8-1_amd64.deb

FDB_SERVER_PKG='foundationdb-server_6.1.8-1_amd64.deb'
FDB_SERVER_SHA384='6be8d6d3f2078767071564e1fe941790ad4a7281efc1422e4fa371869b6049d62ebfbde7a246577a17f140c72413bf3c'
log "Making sure ${FDB_SERVER_PKG} is in appscale cache"
cachepackage "${FDB_SERVER_PKG}" "${FDB_SERVER_SHA384}"

log "Installing ${FDB_SERVER_PKG}"
dpkg --install ${PACKAGE_CACHE}/foundationdb-server_6.1.8-1_amd64.deb
rm ${PACKAGE_CACHE}/foundationdb-server_6.1.8-1_amd64.deb

log "Disabling foundationdb service for now"
/etc/init.d/foundationdb stop
update-rc.d foundationdb disable
