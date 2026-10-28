#!/usr/bin/env bash
# @file init_system.sh
# @brief Library `init` to manage services of init systems
# @description Library `init` to manage services of init systems, covering systemd,
# OpenRC and the service managers of the other supported distributions.
dybatpho::load privilege

#######################################
# @description Enable systemd service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
#######################################
function init_system::enable_systemd_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command systemctl; then
    dybatpho::warn "systemctl command not found, cannot enable service ${service}"
    return
  fi
  dybatpho::progress "Enabling service ${service}"

  if systemctl is-system-running > /dev/null; then
    if dybatpho::is true "${is_user_service}"; then
      systemctl enable --now --user "${service}"
    else
      # Enabling a system unit is a root-only action
      dybatpho::privilege_run -- systemctl enable --now "${service}"
    fi
  fi
}

#######################################
# @description Enable openrc service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
#######################################
function init_system::enable_openrc_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command rc-service; then
    dybatpho::warn "rc-service command not found, cannot enable service ${service}"
    return
  fi
  dybatpho::progress "Enabling service ${service}"
  if dybatpho::is true "${is_user_service}"; then
    rc-update --user add "${service}"
  else
    local cgroup_contents=""
    if dybatpho::is file /proc/self/cgroup; then
      cgroup_contents="$(< /proc/self/cgroup)"
    fi
    # Adding a system runlevel entry needs root
    dybatpho::privilege_run -- rc-update add "${service}" default
    if ! dybatpho::string_contains "${cgroup_contents}" "docker" \
      && ! dybatpho::is file /.dockerenv; then
      # Starting a system service needs root
      dybatpho::privilege_run -- rc-service "${service}" start
    fi
  fi
}

#######################################
# @description Enable termux service
# @arg $1 string Name of service
#######################################
function init_system::enable_termux_service {
  local service
  dybatpho::expect_args service -- "$@"
  if ! dybatpho::is command sv; then
    dybatpho::warn "sv command not found, cannot enable service ${service}"
    return
  fi
  dybatpho::progress "Enabling service ${service}"
  sv-enable "${service}"
  sv up "${service}"
}

#######################################
# @description Enable launchd service on MacOS
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
# @arg $3 string Name of application (optional, used for user-specific services)
#######################################
function init_system::enable_launchd_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command launchctl; then
    dybatpho::warn "launchctl command not found, cannot enable service ${service}"
    return 1
  fi
  dybatpho::progress "Enabling service ${service}"
  if dybatpho::is true "${is_user_service}"; then
    local login_item action
    login_item="{name:\"${service}.app\", path:\"/Applications/${service}.app\","
    login_item+=" kind:\"Application\", hidden:true}"
    action="make new login item at end with properties ${login_item}"
    /usr/bin/osascript -e "tell application \"System Events\" to ${action}"
  else
    brew services start "${service}"
  fi
}

#######################################
# @description Reload the systemd user manager, then enable and start some of
# its units. It skips with a warning when no user manager answers, as on a
# machine booted with another init system or in a container. Unlike
# `is-system-running`, the check still passes on a degraded manager.
# @arg $@ string Names of the units
#######################################
function init_system::enable_systemd_user_units {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: no unit given"
  if ! dybatpho::is command systemctl \
    || ! systemctl --user show-environment &> /dev/null; then
    dybatpho::warn "The systemd user manager is not running, cannot enable $*"
    return 0
  fi
  dybatpho::progress "Enabling $*"
  systemctl --user daemon-reload
  systemctl --user enable --now "$@"
}

#######################################
# @description Load a launchd agent of the logged-in user from its plist,
# unloading the copy loaded before so that a changed plist takes effect.
# @arg $1 string Path of the plist
# @exitcode 1 launchctl is missing
#######################################
function init_system::bootstrap_launchd_agent {
  local plist
  dybatpho::expect_args plist -- "$@"
  if ! dybatpho::is command launchctl; then
    dybatpho::warn "launchctl command not found, cannot load ${plist}"
    return 1
  fi
  local domain
  domain="gui/$(id -u)"
  dybatpho::progress "Loading launchd agent ${plist##*/}"
  # Fails when the agent is not loaded yet, as on the first apply
  launchctl bootout "${domain}" "${plist}" &> /dev/null || true
  launchctl bootstrap "${domain}" "${plist}"
}
