#!/usr/bin/env bash
# Installs Postgres server package.

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"
source "$(dirname ${SCRIPT_DIR})/common.sh"

log "Installing Postgres"
attempt=1
while ! (yes | apt-get install postgresql)
do
    if (( attempt > 15 )); then
        log "Failed to install postgresql after ${attempt} attempts" "ERROR"
        exit 1
    fi
    log "Failed to install postgresql. Retrying." "WARNING"
    ((attempt++))
    sleep ${attempt}
done

log "Disabling Postgres service for now"
systemctl disable postgresql.service
systemctl stop postgresql.service
