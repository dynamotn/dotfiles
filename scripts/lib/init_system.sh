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
  dybatpho::progress "Enabling service $service"
  if dybatpho::is true "$is_user_service"; then
    systemctl enable --now --user "$service"
  else
    sudo systemctl enable --now "$service"
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
  dybatpho::progress "Enabling service $service"
  if dybatpho::is true "$is_user_service"; then
    rc-update --user add "$service"
  else
    sudo rc-update add "$service" default
    sudo rc-service "$service" start
  fi
}

#######################################
# @description Enable termux service
# @arg $1 string Name of service
#######################################
function init::enable_termux_service {
  local service
  dybatpho::expect_args service -- "$@"
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
  dybatpho::progress "Enabling service $service"
  if dybatpho::is true "$is_user_service"; then
    /usr/bin/osascript -e "tell application \"System Events\" to make new login item at end with properties {name:\"${service}.app\", path:\"/Applications/${service}.app\", kind:\"Application\", hidden:true}"
  else
    brew services start "$service"
  fi
}
