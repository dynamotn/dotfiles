# @file network.sh
# @brief Fit git and the proxy to the network the machine is on
# @description Which git remotes and which proxy work depend on the network,
# not on the machine: an office network blocks GitLab or port 22, and only
# that network reaches its proxy. `network::detect` probes the network it is
# on and writes what it found as files read at run time, not at apply time:
#
# - `git.config`: `url.<base>.insteadOf` rules, included by `git/config`, that
#   send GitHub and GitLab over SSH on port 22, over SSH on port 443
#   (ssh.github.com, altssh.gitlab.com) when port 22 is blocked, or over HTTPS
# - `proxy.fish`: the proxy variables, reloaded by fish at its prompt
#
# It runs on every network change (the NetworkManager dispatcher on Linux,
# Hammerspoon on macOS), after every apply, and by hand as `dynet`.
# Sourced (not executed); the caller sources dybatpho first, with the
# `network` and `file` modules, and `yq` installed.
# shellcheck shell=bash

# Seconds a probe waits for a connection before it calls the target down.
NETWORK_PROBE_TIMEOUT="${NETWORK_PROBE_TIMEOUT:-3}"

#######################################
# @description Tell whether a proxy accepts connections from this network
# @arg $1 string Proxy URL, such as http://proxy:3128
# @exitcode 0 The proxy port accepts a connection
# @exitcode 1 It does not, or the URL cannot be parsed
#######################################
function network::proxy_up {
  local proxy
  dybatpho::expect_args proxy -- "$@"
  dybatpho::url_parse "${proxy}" || return 1
  local scheme host port default_port=80
  scheme="$(dybatpho::url_part scheme)"
  if [[ "${scheme}" == "https" ]]; then
    default_port=443
  fi
  host="$(dybatpho::url_part host)"
  port="$(dybatpho::url_part port "${default_port}")"
  dybatpho::port_open "${host}" "${port}" "${NETWORK_PROBE_TIMEOUT}"
}

#######################################
# @description Tell whether the SSH server of a git host is reachable, at the
# host name and port `~/.ssh/config` gives it (such as ssh.github.com:443)
# @arg $1 string Host, as git writes it in `git@<host>:`
# @exitcode 0 An SSH handshake with it gets through
# @exitcode 1 It does not
#######################################
function network::ssh_up {
  local host
  dybatpho::expect_args host -- "$@"
  # An open port is not enough: a network can pass the TCP connection and the
  # banner, then reset the key exchange. A fresh connection (no multiplexed
  # master hides the network) that gets as far as host key or user
  # authentication proves it; that it then refuses the key is not the network.
  # It also replaces a /dev/tcp port probe, which macOS kills for some hosts.
  local answer
  answer="$(timeout "$((NETWORK_PROBE_TIMEOUT * 3))" ssh -T -o BatchMode=yes -o ControlMaster=no \
    -o ControlPath=none -o StrictHostKeyChecking=yes -o ConnectTimeout="${NETWORK_PROBE_TIMEOUT}" \
    "git@${host}" < /dev/null 2>&1)" || true
  grep -Eq 'Permission denied|Host key verification failed|Welcome to GitLab|successfully authenticated' \
    <<< "${answer}"
}

#######################################
# @description Print the first of the SSH hosts of a git host that git
# reaches: the host itself on port 22, then its fallback on port 443
# @arg $@ string Hosts to try, in order
# @stdout The first one reachable, nothing when none is
#######################################
function network::ssh_host {
  local host
  dybatpho::expect_args host -- "$@"
  for host in "$@"; do
    if network::ssh_up "${host}"; then
      printf '%s\n' "${host}"
      return 0
    fi
  done
}

#######################################
# @description Tell whether an HTTPS site answers, through the proxy in the
# environment if any; a block page with an error status counts as down
# @arg $1 string URL
# @exitcode 0 The site answered with a success or a redirect
# @exitcode 1 It did not
#######################################
function network::https_up {
  local url
  dybatpho::expect_args url -- "$@"
  curl --fail --silent --head --output /dev/null \
    --connect-timeout "${NETWORK_PROBE_TIMEOUT}" \
    --max-time "$((NETWORK_PROBE_TIMEOUT * 2))" "${url}"
}

#######################################
# @description Print a field of dynet's config. It is read with `yq`, which
# setup.sh installs on a fresh machine, where there is no `jq` yet.
# @arg $1 string Config of dynet, a JSON file
# @arg $2 string yq expression
# @stdout The field, unquoted
#######################################
function __network_config {
  local config expression
  dybatpho::expect_args config expression -- "$@"
  yq -p=json -o=yaml -r "${expression}" "${config}"
}

#######################################
# @description Print one `url.<base>.insteadOf` rule of git
# @arg $1 string URL git uses
# @arg $@ string URLs it stands for
# @stdout The rule, in git config syntax
#######################################
function __network_insteadof {
  local to
  dybatpho::expect_args to -- "$@"
  shift
  printf '[url "%s"]\n' "${to}"
  local from
  for from in "$@"; do
    printf '        insteadOf = %s\n' "${from}"
  done
}

#######################################
# @description Print the rule that sends every URL of a git host, over HTTPS,
# SSH or SSH on port 443, the one way the network lets through
# @arg $1 string Host, such as github.com
# @arg $2 string Its SSH host on port 443, such as ssh.github.com
# @arg $3 string SSH host git reaches, one of the two; empty for HTTPS
# @stdout The rule, in git config syntax
#######################################
function __network_git_host {
  local host fallback ssh_host
  dybatpho::expect_args host fallback ssh_host -- "$@"
  local https="https://${host}/" ssh="git@${host}:" alt="git@${fallback}:"
  if [[ -z "${ssh_host}" ]]; then
    __network_insteadof "${https}" "${ssh}" "${alt}"
  elif [[ "${ssh_host}" == "${host}" ]]; then
    __network_insteadof "${ssh}" "${https}" "${alt}"
  else
    __network_insteadof "${alt}" "${https}" "${ssh}"
  fi
}

#######################################
# @description Print the git URL rewrites that fit the network: GitHub and
# GitLab each over SSH on port 22, over SSH on port 443 when only that gets
# through, or over HTTPS, whichever URL a remote or a `.gitmodules` names.
# A repository mirrored on both keeps its two remotes, `origin` on GitLab and
# `gh` on GitHub (scripts/lib/mirror.sh): neither is sent to the other host.
# @arg $1 string SSH host git reaches GitHub at (github.com, ssh.github.com), empty for HTTPS
# @arg $2 string SSH host git reaches GitLab at (gitlab.com, altssh.gitlab.com), empty for HTTPS
# @stdout The rules, in git config syntax
#######################################
function network::git_config {
  local github_ssh gitlab_ssh
  dybatpho::expect_args github_ssh gitlab_ssh -- "$@"
  __network_git_host github.com ssh.github.com "${github_ssh}"
  __network_git_host gitlab.com altssh.gitlab.com "${gitlab_ssh}"
}

#######################################
# @description Print the proxy variables for fish: set when a proxy is given,
# erased otherwise, so a shell that sources it follows the network both ways
# @arg $1 string Proxy URL, empty for none
# @arg $2 string Comma-separated hosts that bypass the proxy
# @stdout fish commands
#######################################
function network::proxy_fish {
  local proxy no_proxy
  dybatpho::expect_args proxy no_proxy -- "$@"
  printf 'set -e http_proxy https_proxy no_proxy\n'
  [[ -n "${proxy}" ]] || return 0
  local name value
  for name in http_proxy https_proxy no_proxy; do
    value="${proxy}"
    if [[ "${name}" == "no_proxy" ]]; then
      value="${no_proxy}"
    fi
    value="${value//\\/\\\\}"
    printf "set -gx %s '%s'\n" "${name}" "${value//\'/\\\'}"
  done
}

#######################################
# @description Probe the network and write `git.config` and `proxy.fish` for
# it. The proxy found is also exported, or the inherited one unset, so a
# caller that runs this in its own shell downloads the way the network allows.
# @arg $1 string Config of dynet: a JSON file with `.preferGitSSH`,
# `.httpProxy` and `.noProxyAddresses`
# @arg $2 string Directory to write the files into
# @set http_proxy string The proxy, when it is reachable
# @set https_proxy string The proxy, when it is reachable
# @set no_proxy string Hosts that bypass it, when it is reachable
#######################################
function network::detect {
  local config state
  dybatpho::expect_args config state -- "$@"
  local prefer_ssh proxy no_proxy_hosts
  prefer_ssh="$(__network_config "${config}" '.preferGitSSH')"
  proxy="$(__network_config "${config}" '.httpProxy // ""')"
  no_proxy_hosts="$(__network_config "${config}" '(.noProxyAddresses // []) | join(",")')"

  # The proxy is probed first: whether GitLab answers may depend on it.
  if [[ -n "${proxy}" ]] && network::proxy_up "${proxy}"; then
    export http_proxy="${proxy}" https_proxy="${proxy}" no_proxy="${no_proxy_hosts}"
  else
    unset http_proxy https_proxy no_proxy
    proxy=""
  fi
  local github_ssh="" gitlab_up=false gitlab_ssh=""
  if dybatpho::is true "${prefer_ssh}"; then
    github_ssh="$(network::ssh_host github.com ssh.github.com)"
  fi
  if network::https_up "https://gitlab.com/"; then
    gitlab_up=true
    if dybatpho::is true "${prefer_ssh}"; then
      gitlab_ssh="$(network::ssh_host gitlab.com altssh.gitlab.com)"
    fi
  fi

  local git_config proxy_fish
  git_config="$(network::git_config "${github_ssh}" "${gitlab_ssh}")"
  proxy_fish="$(network::proxy_fish "${proxy}" "${no_proxy_hosts}")"
  dybatpho::ensure_dir "${state}" > /dev/null
  # proxy.fish may hold the credentials of the proxy.
  (
    umask 077
    dybatpho::file_write_atomic "${state}/git.config" <<< "${git_config}"
    dybatpho::file_write_atomic "${state}/proxy.fish" <<< "${proxy_fish}"
  )
  local proxy_state="off"
  if [[ -n "${proxy}" ]]; then
    proxy_state="on"
  fi
  local found="proxy: ${proxy_state}, GitHub SSH: ${github_ssh:-none}"
  found+=", GitLab: ${gitlab_up}, GitLab SSH: ${gitlab_ssh:-none}"
  dybatpho::info "${found}"
}
