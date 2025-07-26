#!/bin/bash
# shellcheck disable=2154

#######################################
# @description Detects the init system used by the operating system
# @stdout Name of init system (e.g., systemd, sysvinit, openrc)
#######################################
function _detect_init_system {
  if command -v systemctl &> /dev/null; then
    result="systemd"
  elif command -v rc-service &> /dev/null; then
    result="openrc"
  else
    result="unknown"
  fi
  dybatpho::debug "Detected init system: ${result}"
  echo "${result}"
}

#######################################
# @description Enable systemd service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (true) or user-
# specific (false)
#######################################
function _enable_systemd_service {
  dybatpho::expect_args service is_system -- "$@"
  dybatpho::progress "Enabling service $service"
  if dybatpho::is false "$is_system"; then
    systemctl enable --now --user "$service"
  else
    sudo systemctl enable --now "$service"
  fi
}

#######################################
# @description Enable sysvinit service
# @arg $1 string Name of service
#######################################
function _enable_sysvinit_service {
  dybatpho::expect_args service -- "$@"
  dybatpho::progress "Enabling service $service"
  sudo service "$service" enable
  sudo service "$service" start
}

#######################################
# @description Enable openrc service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (true) or user-
# specific (false)
#######################################
function _enable_openrc_service {
  dybatpho::expect_args service is_system -- "$@"
  dybatpho::progress "Enabling service $service"
  if dybatpho::is false "$is_system"; then
    rc-update --user add "$service"
  else
    sudo rc-update add "$service" default
    sudo rc-service "$service" start
  fi
}

#######################################
# @description Enable service on Gentoo
# @see _enable_systemd_service, _enable_openrc_service
#######################################
function _gentoo_enable_service {
  case $(_detect_init_system) in
    systemd)
      _enable_systemd_service "$@"
      ;;
    openrc)
      _enable_openrc_service "$@"
      ;;
    *)
      dybatpho::die "Unsupported init system: $(_detect_init_system)"
      ;;
  esac
}

#######################################
# @description Enable service on Arch
# @see _enable_systemd_service
#######################################
function _arch_enable_service {
  _enable_systemd_service "$@"
}

#######################################
# @description Enable service on Ubuntu
# @see _enable_systemd_service
#######################################
function _ubuntu_enable_service {
  _enable_systemd_service "$@"
}

#######################################
# @description Enable service on Termux
# @see _enable_openrc_service
#######################################
function _alpine_enable_service {
  _enable_openrc_service "$@"
}
#######################################
# @description Enable termux service
# @arg $1 string Name of service
#######################################
function _termux_enable_service {
  dybatpho::expect_args service -- "$@"
  dybatpho::progress "Enabling service $service"
  sv-enable "$service"
  sv up "$service"
}

#######################################
# @description Enable macos service
# @arg $1 string Name of service
# @arg $2 boolean Flag indicating if the service is system-wide (true) or user-
# specific (false)
# @arg $3 string Name of application (optional, used for user-specific services)
#######################################
function _macos_enable_service {
  dybatpho::expect_args service is_system -- "$@"
  shift 2
  dybatpho::progress "Enabling service $service"
  if dybatpho::is false "$is_system"; then
    dybatpho::expect_args app -- "$@"
    /usr/bin/osascript -e "tell application \"System Events\" to make new login item at end with properties {name:\"${service}.app\", path:\"/Applications/${service}.app\", kind:\"Application\", hidden:true}"
  else
    brew services start "$service"
  fi
}
