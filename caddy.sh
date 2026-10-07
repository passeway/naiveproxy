#!/usr/bin/env bash
# Compatibility entry point: use the same verified downloader as the manager.
set -o pipefail
manager_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
if [ -f "$manager_dir/naive.sh" ]; then
    exec bash "$manager_dir/naive.sh" --core-only
fi
stage=$(mktemp -d) || exit 1
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP
curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    https://raw.githubusercontent.com/passeway/naiveproxy/main/naive.sh -o "$stage/naive.sh" || exit 1
bash "$stage/naive.sh" --core-only
