#!/usr/bin/env bash
# @file pins.sh
# @brief Check the sha256 digests pinned beside a version
# @description Download every asset whose digest the repository pins (age
# and yq in setup.sh and age.yaml.tmpl, the delta theme) and fail when one
# does not match, printing the digest to write. Runs in CI on any pull
# request that touches a pin, such as a Renovate bump.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules network file
# shellcheck source=lib/pins.sh
. "${SCRIPT_DIR}/lib/pins.sh"
dybatpho::register_common_handlers

ROOT_DIR="$(dybatpho::path_normalize "${SCRIPT_DIR}/..")"
# dyshellint disable=SC2310 the status is the answer, reported in the message below
pins::check "${ROOT_DIR}" || dybatpho::die "Write the digests above, which the new versions publish"
dybatpho::success "Every pinned digest matches"
