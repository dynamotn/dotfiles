#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BATS_CMD="${ROOT_DIR}/scripts/lib/dybatpho/test/lib/core/bin/bats"

if [ "$#" -eq 0 ]; then
  exec "${BATS_CMD}" --print-output-on-failure --verbose-run "${SCRIPT_DIR}"
fi

exec "${BATS_CMD}" --print-output-on-failure --verbose-run "$@"
