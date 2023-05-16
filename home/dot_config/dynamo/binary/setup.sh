#!/bin/bash
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
export BIN_DIR=$HOME/.local/bin
export MAN_DIR=$HOME/.local/man

_usage() {
  echo "$0 usage:" && grep " .)\\ #" "$0" | sed -e 's/\(.\)) #/-\1/g'
  exit 0
}

_parse_args() {
  while getopts ":hnms:" arg; do
    case $arg in
      n) # Update only not existed command
        NOT_EXIST_ONLY=true
        ;;
      m) # Update only must-needed command
        MUST_NEEDED=true
        ;;
      h) # Display help
        _usage
        ;;
      s) # Only one specific tool
        PACKAGE=$OPTARG
        ;;
      *) ;;
    esac
  done
}

_update() {
  # $1: URL of file
  # $2: File name of command
  # $3: Flag check is installed by helper file
  if [ "$NOT_EXIST_ONLY" = true ] && [ -f "$BIN_DIR/$2" ]; then
    return
  fi
  if [ "$3" = true ]; then
    TEMP=$(mktemp)
    export TEMP
    curl -SL "$1" -o "$TEMP" && bash "$SCRIPT_DIR/helpers/$2.sh"
    rm -rf "$TEMP"
  else
    curl -SL "$1" -o "$BIN_DIR/$2"
  fi
  chmod +x "$BIN_DIR/$2"
}

_update_github_release() {
  # $1: Repository string on GitHub
  # $2: Version of GitHub Release
  # $3: File name in GitHub Release URLs
  # $4: Output file name of command
  # $5: Flag check is installed by helper file
  # $6: Flag check is must-have tool
  if [ "$MUST_NEEDED" = true ] && [ "$6" != true ]; then
    return
  fi
  echo "Checking $4"
  if test "$2" = ""; then
    VERSION=$(curl -sSL -u "$GITHUB_API_USERNAME:$GITHUB_API_TOKEN" https://api.github.com/repos/"$1"/releases/latest | grep -Po "tag_name\": \"(\K.*)(?=\",)")
  else
    VERSION=$2
  fi
  export VERSION
  if [ "$VERSION" = "" ]; then
    echo "Version is not specified or you're limited request to Github API"
    exit 1
  else
    echo "Using version $VERSION for https://github.com/$1"
  fi
  _update "https://github.com/$1/releases/download/$VERSION/$(eval "echo $3")" "$4" "$5"
}

_main() {
  # Update command by get release file
  tail -n +2 "$SCRIPT_DIR"/linux/data.csv | grep -isP ",$PACKAGE($|,)" | while IFS=, read -r github_repo version asset_file file_name has_helper must_needed; do
    _update_github_release "$github_repo" "$version" "$asset_file" "$file_name" "$has_helper" "$must_needed"
  done
}

_parse_args "$@"

GITHUB_API_USERNAME=${GITHUB_API_USERNAME:-dynamotn}
GITHUB_API_TOKEN=${GITHUB_API_TOKEN:-}
_main
