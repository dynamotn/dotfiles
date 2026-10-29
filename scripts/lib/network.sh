# @file network.sh
# @brief Fit git and the proxy to the network the machine is on
# @description Which git remotes and which proxy work depend on the network,
# not on the machine: an office network blocks GitLab or port 22, and only
# that network reaches its proxy. `network::detect` probes the network it is
# on and writes what it found as files read at run time, not at apply time:
#
# - `git.config`: `url.<base>.insteadOf` rules, included by `git/config`
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
# @description Print the git URL rewrites that fit the network. GitHub and
# GitLab are each reached over SSH or HTTPS, and every repository mirrored on
# both goes to GitLab while it is reachable and to GitHub otherwise, whichever
# of their four URLs a remote or a `.gitmodules` names. git applies the
# longest matching rule alone, so a mirror's rule beats its host's.
# @arg $1 bool Whether git reaches GitHub over SSH
# @arg $2 bool Whether GitLab is reachable at all
# @arg $3 bool Whether git reaches GitLab over SSH
# @arg $4 string Config of dynet, a JSON file with `.mirrors`
# @stdout The rules, in git config syntax
#######################################
function network::git_config {
  local github_ssh gitlab_up gitlab_ssh config
  dybatpho::expect_args github_ssh gitlab_up gitlab_ssh config -- "$@"
  local -A base=(
    [github_ssh]="git@github.com:"
    [github_https]="https://github.com/"
    [gitlab_ssh]="git@gitlab.com:"
    [gitlab_https]="https://gitlab.com/"
  )
  local host uses_ssh
  for host in github gitlab; do
    uses_ssh="${host}_ssh"
    if dybatpho::is true "${!uses_ssh}"; then
      __network_insteadof "${base[${host}_ssh]}" "${base[${host}_https]}"
    else
      __network_insteadof "${base[${host}_https]}" "${base[${host}_ssh]}"
    fi
  done

  local target="github"
  if dybatpho::is true "${gitlab_up}"; then
    target="gitlab"
  fi
  local protocol="https"
  uses_ssh="${target}_ssh"
  if dybatpho::is true "${!uses_ssh}"; then
    protocol="ssh"
  fi
  # shortcut: a rule matches by prefix, so it also catches an unlisted
  # repository whose name extends a listed one; list that repository too.
  local mirrors gitlab github form
  local -A path
  local -a from
  mirrors="$(__network_config "${config}" '.mirrors[] | .gitlab + " " + .github')"
  while read -r gitlab github; do
    [[ -n "${gitlab}" ]] || continue
    path=([gitlab]="${gitlab}" [github]="${github}")
    from=()
    for form in github_ssh github_https gitlab_ssh gitlab_https; do
      if [[ "${form}" != "${target}_${protocol}" ]]; then
        from+=("${base[${form}]}${path[${form%_*}]}")
      fi
    done
    __network_insteadof "${base[${target}_${protocol}]}${path[${target}]}" ${from[@]+"${from[@]}"}
  done <<< "${mirrors}"
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
# `.httpProxy`, `.noProxyAddresses` and `.mirrors`
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
  local github_ssh=false gitlab_up=false gitlab_ssh=false
  if dybatpho::is true "${prefer_ssh}" && network::ssh_up github.com; then
    github_ssh=true
  fi
  if network::https_up "https://gitlab.com/"; then
    gitlab_up=true
    if dybatpho::is true "${prefer_ssh}" && network::ssh_up gitlab.com; then
      gitlab_ssh=true
    fi
  fi

  local git_config proxy_fish
  git_config="$(network::git_config "${github_ssh}" "${gitlab_up}" "${gitlab_ssh}" "${config}")"
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
  dybatpho::info "proxy: ${proxy_state}, GitHub SSH: ${github_ssh}, GitLab: ${gitlab_up}, GitLab SSH: ${gitlab_ssh}"
}
