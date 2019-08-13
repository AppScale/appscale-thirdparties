#!/usr/bin/env bash
# This script is used by appscale bootstrap.sh in order to prepare
# all needed artifacts in appscale image.

for script in $(find ./ -name download_artifacts.sh) ; do
  bash ${script}
done
