#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <source-path>" >&2
    exit 1
fi

SOURCE_PATH="$(realpath "$1")"

docker run --rm \
    -v "${SOURCE_PATH}:/workspace" \
    -w /workspace \
    zpr/dev-env \
    cargo build
