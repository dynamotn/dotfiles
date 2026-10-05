#!/usr/bin/env bash
# @file kernel.sh
# @brief Configure, build and install a gentoo-sources kernel
# @description Write the kernel `.config` from the base defconfig and tuning
# fragment that chezmoi applies under `/etc/kernel/gentoo-sources`, refuse to
# go on when Kconfig dropped any option the fragment asks for, then build and
# install the kernel. Out-of-tree modules are rebuilt before `make install`,
# because installkernel runs dracut, which must find the NVIDIA modules to put
# them in the initramfs. The previous kernel is left in place as a fallback.
# The upper-case options are assigned by dybatpho::opts from _spec_main.
# shellcheck disable=SC2153,SC2154
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# The library lives in a submodule, which a fresh clone or a new worktree
# does not populate. Fetch it before sourcing, or nothing below is defined.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${SCRIPT_DIR}/.." submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli privilege
# shellcheck source=lib/kernel.sh
. "${SCRIPT_DIR}/lib/kernel.sh"
dybatpho::register_common_handlers
shopt -s inherit_errexit

#######################################
# @description Spec of kernel.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Configure, build and install a gentoo-sources kernel" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::param "Kernel source directory" SOURCE_DIR --source -s init:="/usr/src/linux"
  dybatpho::opts::param "Directory holding base.config and tuning.config" \
    CONFIG_DIR --config-dir -c init:="/etc/kernel/gentoo-sources"
  dybatpho::opts::param "Number of parallel build jobs" JOBS --jobs -j init:=""
  dybatpho::opts::flag "Only write and verify .config, build nothing" \
    CONFIGURE_ONLY --configure-only -n on:true off:false init:="false"
  dybatpho::opts::flag "Open menuconfig after merging, then verify again" \
    MENUCONFIG --menuconfig -m on:true off:false init:="false"
  dybatpho::opts::param "Save the resulting .config as a defconfig to this path" \
    SAVE_BASE --save-base -b init:=""
  dybatpho::opts::flag "Skip configure and build: rebuild out-of-tree modules and install" \
    INSTALL_ONLY --install-only -i on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Fail when the tree's .config lost an option of the fragment
# @arg $1 string Path of the tuning fragment
#######################################
function _verify {
  local fragment
  dybatpho::expect_args fragment -- "$@"
  local config mismatches status=0
  config="$(dybatpho::path_join "${SOURCE_DIR}" ".config")"
  # The mismatch list is the output wanted here, so errexit stays out of it.
  # shellcheck disable=SC2310
  mismatches="$(kernel::verify_config "${config}" "${fragment}")" || status=$?
  if ((status != 0)); then
    dybatpho::warn "Kconfig did not keep these options of ${fragment}:"
    printf '%s\n' "${mismatches}" >&2
    dybatpho::die "Fix the fragment or its missing dependencies before building"
  fi
  dybatpho::success "Every option of ${fragment} is in effect"
}

#######################################
# @description Main function
# @noargs
#######################################
function _main {
  local base fragment cpus
  base="$(dybatpho::path_join "${CONFIG_DIR}" "base.config")"
  fragment="$(dybatpho::path_join "${CONFIG_DIR}" "tuning.config")"
  if [[ -z "${JOBS}" ]]; then
    cpus="$(dybatpho::cpu_count || printf '4')"
    JOBS="$((cpus + 1))"
  fi
  dybatpho::require "make"
  # Checked before anything is written: a wrong tree must stay untouched.
  # shellcheck disable=SC2310
  kernel::check_tree "${SOURCE_DIR}" \
    || dybatpho::die "Install sys-kernel/gentoo-sources (USE=symlink) or pass --source"

  # Root is needed to write a root-owned tree, and to install anything at all.
  if dybatpho::privilege_needed \
    && { [[ ! -w "${SOURCE_DIR}" ]] || [[ "${CONFIGURE_ONLY}" != "true" ]]; }; then
    dybatpho::privilege_acquire || dybatpho::die "Installing a kernel needs root"
  fi

  if [[ "${INSTALL_ONLY}" == "true" ]]; then
    # Resume after an interrupted run, on the tree that was built then.
    _verify "${fragment}"
    _install
    return
  fi

  dybatpho::header "Configure ${SOURCE_DIR}"
  kernel::merge_config "${SOURCE_DIR}" "${base}" "${fragment}"
  if [[ "${MENUCONFIG}" == "true" ]]; then
    kernel::run_in_tree "${SOURCE_DIR}" -- make -C "${SOURCE_DIR}" menuconfig
  fi
  _verify "${fragment}"
  if [[ -n "${SAVE_BASE}" ]]; then
    kernel::save_defconfig "${SOURCE_DIR}" "${SAVE_BASE}"
    dybatpho::success "Saved defconfig to ${SAVE_BASE}"
  fi
  if [[ "${CONFIGURE_ONLY}" == "true" ]]; then
    return
  fi

  dybatpho::header "Build kernel with ${JOBS} jobs"
  kernel::run_in_tree "${SOURCE_DIR}" -- make -C "${SOURCE_DIR}" -j "${JOBS}"
  # Strip only the DWARF: the BTF sections that bcc and sched_ext read stay.
  # dyshellint disable=BSG035 modules_install writes to /lib/modules
  dybatpho::privilege_run -- make -C "${SOURCE_DIR}" INSTALL_MOD_STRIP=1 modules_install
  _install
}

#######################################
# @description Rebuild the out-of-tree modules, then install the kernel
# @noargs
#######################################
function _install {
  local tree linux release
  # linux-mod-r1 builds the out-of-tree modules against /usr/src/linux.
  tree="$(realpath "${SOURCE_DIR}")"
  linux="$(realpath /usr/src/linux || true)"
  if [[ "${tree}" != "${linux}" ]]; then
    dybatpho::warn "/usr/src/linux does not point at ${SOURCE_DIR}; @module-rebuild will target another tree"
  fi

  if dybatpho::is command emerge; then
    dybatpho::header "Rebuild out-of-tree modules"
    # Keep the --ask of EMERGE_DEFAULT_OPTS where someone can answer it: the
    # merge list and progress stay visible, and a stuck run can be told apart
    # from a slow one.
    local -a ask=()
    dybatpho::is_tty stdin || ask=(--ask=n)
    # dyshellint disable=BSG035 emerge writes to the system package database
    dybatpho::privilege_run -- emerge ${ask[@]+"${ask[@]}"} --oneshot @module-rebuild
  fi

  dybatpho::header "Install kernel"
  # installkernel generates the initramfs with dracut and updates GRUB.
  # dyshellint disable=BSG035 make install writes to /boot
  dybatpho::privilege_run -- make -C "${SOURCE_DIR}" install
  release="$(make -s -C "${SOURCE_DIR}" kernelrelease)"
  dybatpho::success "Kernel ${release} installed; the previous one stays in GRUB"
}

dybatpho::generate_from_spec _spec_main "$@"
