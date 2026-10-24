#!/usr/bin/env bash
# @file lima-image.sh
# @brief Build my own Arch Linux ARM image for the Lima templates
# @description Starts a throwaway Ubuntu VM in Lima, runs
#   `lima-image-build.sh` in it to pacstrap a current Arch Linux ARM system,
#   and points `Arch-Linux-aarch64-cloudimg-latest.qcow2` at the result, which
#   is the image `~/.lima/_templates/_images/archlinux.yaml` boots.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
# The library lives in a submodule, which a fresh clone or a new worktree
# does not populate. Fetch it before sourcing, or nothing below is defined.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${REPO_DIR}" submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli
dybatpho::register_common_handlers

#######################################
# @description Spec of lima-image.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Build an Arch Linux ARM image for Lima" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Directory that keeps the images" OUTPUT_DIR --output -o \
    init:="${HOME}/.local/share/lima/images"
  dybatpho::opts::param "Name of the builder VM" BUILDER --builder -b init:="alarm-builder"
  dybatpho::opts::flag "Keep the builder VM afterwards" KEEP_BUILDER --keep -k \
    on:true off:false init:="false"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Delete the builder VM, unless asked to keep it
# @noargs
#######################################
# dyshellint disable=SC2154 BUILDER and KEEP_BUILDER are assigned by dybatpho::opts from _spec_main
function _remove_builder {
  [[ "${KEEP_BUILDER}" == "true" ]] && return 0
  limactl delete --force "${BUILDER}" &> /dev/null || true
}

#######################################
# @description Main function
# @noargs
#######################################
# dyshellint disable=SC2154 OUTPUT_DIR and BUILDER are assigned by dybatpho::opts from _spec_main
function _main {
  local name image latest machine instances
  dybatpho::require "limactl"
  machine="$(uname -m)"
  [[ "${machine}" == "arm64" ]] || dybatpho::die "Only Apple silicon hosts build aarch64 images"
  [[ -z "${LIMA_INSTANCE:-}" ]] || dybatpho::die "Run this on the host, not inside a Lima VM"
  mkdir -p "${OUTPUT_DIR}"

  # A builder left over from an earlier run would keep its old mounts
  instances="$(limactl list --quiet 2> /dev/null)"
  if grep -qx "${BUILDER}" <<< "${instances}"; then
    dybatpho::die "Lima instance ${BUILDER} already exists; delete it or pass --builder"
  fi
  dybatpho::trap _remove_builder EXIT

  dybatpho::header "Starting builder ${BUILDER}"
  limactl start --tty=false --name "${BUILDER}" --containerd none \
    --cpus 4 --memory 4 --disk 20 \
    --mount-only "${REPO_DIR}" --mount-only "${OUTPUT_DIR}:w" \
    template:ubuntu

  name="Arch-Linux-aarch64-cloudimg-$(date -u '+%Y%m%d')"
  image="$(dybatpho::path_join "${OUTPUT_DIR}" "${name}.qcow2")"
  limactl shell --workdir / "${BUILDER}" \
    sudo bash "${SCRIPT_DIR}/lima-image-build.sh" \
    --output "${OUTPUT_DIR}" --log-level "${LOG_LEVEL}"
  dybatpho::is file "${image}" || dybatpho::die "The builder wrote no ${image}"

  # Not a symlink: Lima clonefile()s a local image, which copies the link
  # itself. An APFS clone is a real file and costs no extra space; the BSD
  # cp is named because a GNU cp earlier on PATH has no -c.
  latest="$(dybatpho::path_join "${OUTPUT_DIR}" "Arch-Linux-aarch64-cloudimg-latest.qcow2")"
  rm -f -- "${latest}"
  /bin/cp -c "${image}" "${latest}"
  dybatpho::success "Built ${image}"
  dybatpho::info "New Lima instances based on _images/archlinux now boot it"
}

dybatpho::generate_from_spec _spec_main "$@"
