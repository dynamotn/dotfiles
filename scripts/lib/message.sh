#!/bin/bash
#
if [ "$TERM" == "linux" ]; then
  RED=''
  ORANGE=''
  GREEN=''
  BLUE=''
  PURPLE=''
  CYAN=''
  NC=''
else
  RED='\033[0;31m'
  ORANGE='\033[0;33m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  PURPLE='\033[0;35m'
  CYAN='\033[0;36m'
  NC='\033[0m'
fi

_error_without_exit() {
  echo -e "${RED}ERROR: ${1}${NC}" >&2
}

_error() {
  _error_without_exit "$1"
  exit 1
}

_warning() {
  echo -e "${ORANGE}WARNING: ${1}${NC}"
}

_success() {
  echo -e "${GREEN}DONE: ${1}${NC}"
}

_notice() {
  echo -e "${BLUE}>>>>> ${1} <<<<<${NC}"
}

_progress() {
  echo -e "${CYAN}$1...${NC}"
}

_debug() {
  echo -e "${PURPLE}DEBUG: ${1}${NC}"
}

_info() {
  echo -e "${NC}INFO: ${1}"
}
