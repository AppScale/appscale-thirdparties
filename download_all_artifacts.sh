#!/usr/bin/env bash
# This script is used by appscale bootstrap.sh in order to prepare
# all needed artifacts in appscale image.

SCRIPT_DIR="$( realpath --strip "$( dirname "${BASH_SOURCE[0]}" )" )"

for script in $(find "${SCRIPT_DIR}" -name download_artifacts.sh) ; do
  bash ${script}
done
