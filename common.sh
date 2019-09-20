#!/usr/bin/env bash
# Helpers functions library to be sourced by appscale-thirdparties scripts.

set -eu

PACKAGE_CACHE='/var/cache/appscale'
PACKAGE_MIRROR='http://s3.amazonaws.com/appscale-build'

log() {
    local LEVEL=${2:-INFO}
    echo "$(date +'%Y-%m-%d %T') $LEVEL $1"
}

cachepackage() {
    cached_file="${PACKAGE_CACHE}/$1"
    remote_file="${PACKAGE_MIRROR}/$1"
    expected_sha384="$2"
    mkdir -p ${PACKAGE_CACHE}
    if [ -f ${cached_file} ]; then
        actual_sha384=($(sha384sum ${cached_file}))
        if [ "${actual_sha384}" = "${expected_sha384}" ]; then
            return 0
        else
            log "Incorrect sha384sum for ${cached_file}. Removing it." "ERROR"
            rm ${cached_file}
        fi
    fi

    log "Fetching ${remote_file}"
    if ! curl -fs "${remote_file}" > "${cached_file}"; then
        log "Error while downloading ${remote_file}" "ERROR"
        return 1
    fi

    actual_sha384=($(sha384sum ${cached_file}))
    if [ "${actual_sha384}" = "${expected_sha384}" ]; then
        return 0
    else
        log "sha384 sum of downloaded file is ${actual_sha384} though ${expected_sha384} was expected" "ERROR"
        log "Try downloading package manually to ${cached_file} and running script again"
        rm ${cached_file}
        return 1
    fi
}

export PACKAGE_CACHE
