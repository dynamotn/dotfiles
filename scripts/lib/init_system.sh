#!/usr/bin/env bash
# shellcheck disable=2154

#######################################
# @description Enable systemd service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
#######################################
function init::enable_systemd_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command systemctl; then
    dybatpho::warn "systemctl command not found, cannot enable service $service"
    return
  fi
  dybatpho::progress "Enabling service $service"

  if systemctl is-system-running > /dev/null; then
    if dybatpho::is true "$is_user_service"; then
      systemctl enable --now --user "$service"
    else
      sudo systemctl enable --now "$service"
    fi
  fi
}

#######################################
# @description Enable openrc service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
#######################################
function init::enable_openrc_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command rc-service; then
    dybatpho::warn "rc-service command not found, cannot enable service $service"
    return
  fi
  dybatpho::progress "Enabling service $service"
  if dybatpho::is true "$is_user_service"; then
    rc-update --user add "$service"
  else
    local cgroup_contents=""
    if dybatpho::is file /proc/self/cgroup; then
      cgroup_contents="$(< /proc/self/cgroup)"
    fi
    sudo rc-update add "$service" default
    if ! dybatpho::string_contains "$cgroup_contents" "docker" \
      && ! dybatpho::is file /.dockerenv; then
      sudo rc-service "$service" start
    fi
  fi
}

#######################################
# @description Enable termux service
# @arg $1 string Name of service
#######################################
function init::enable_termux_service {
  local service
  dybatpho::expect_args service -- "$@"
  if ! dybatpho::is command sv; then
    dybatpho::warn "sv command not found, cannot enable service $service"
    return
  fi
  dybatpho::progress "Enabling service $service"
  sv-enable "$service"
  sv up "$service"
}

#######################################
# @description Enable launchd service on MacOS
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (false) or
# user-specific (true)
# @arg $3 string Name of application (optional, used for user-specific services)
#######################################
function init::enable_launchd_service {
  local service is_user_service
  dybatpho::expect_args service is_user_service -- "$@"
  if ! dybatpho::is command launchctl; then
    dybatpho::warn "launchctl command not found, cannot enable service $service"
    return
  fi
  dybatpho::progress "Enabling service $service"
  if dybatpho::is true "$is_user_service"; then
    /usr/bin/osascript -e "tell application \"System Events\" to make new login item at end with properties {name:\"${service}.app\", path:\"/Applications/${service}.app\", kind:\"Application\", hidden:true}"
  else
    local zerobrew_prefix="${ZEROBREW_ROOT:-/opt/zerobrew}"
    local plist_path
    plist_path=$(find "${zerobrew_prefix}/opt/${service}" -name "*.plist" -maxdepth 2 2> /dev/null | head -1)
    if [[ -z "$plist_path" ]]; then
      dybatpho::warn "No service plist found for ${service} in ${zerobrew_prefix}/opt/${service}"
      return
    fi
    local label
    label=$(/usr/libexec/PlistBuddy -c 'Print Label' "$plist_path" 2> /dev/null)
    if [[ -z "$label" ]]; then
      dybatpho::warn "Could not read Label from plist for ${service}"
      return
    fi
    local plist_dest="/Library/LaunchDaemons/${label}.plist"
    if ! launchctl list "$label" &> /dev/null; then
      dybatpho::dry_run sudo cp "$plist_path" "$plist_dest"
      dybatpho::dry_run sudo launchctl bootstrap system "$plist_dest"
    fi
  fi
}
