# @file mirror.sh
# @brief Give a checkout of a mirrored repository its GitLab and GitHub remotes
# @description A repository of its own lives on GitLab and is pushed to a
# GitHub mirror (`git mirror`). ~/.config/dynet/mirrors.json, rendered from
# .chezmoidata/mirrors.yaml, lists their paths on both. A checkout of one gets
# two remotes, `origin` on GitLab and `gh` on GitHub, whichever of them it was
# cloned from: on clone (the post-checkout hook), with `dynet remotes`, and
# with `git mirror`. Whether git then reaches them over SSH, SSH on port 443
# or HTTPS is up to the rules of dynet (network.sh).
# Sourced (not executed); the caller sources dybatpho first, and `yq` is
# installed.
# shellcheck shell=bash

#######################################
# @description Print the forge and the path of a GitLab or GitHub URL, in any
# form git takes: `git@host:path`, `ssh://git@host:port/path` or
# `https://host/path`, at the host itself or at its SSH host on port 443
# @arg $1 string URL
# @stdout `gitlab <path>` or `github <path>`, the path without `.git`
# @exitcode 0 The URL is on GitLab or GitHub
# @exitcode 1 It is not
#######################################
function mirror::parse_url {
  local url
  dybatpho::expect_args url -- "$@"
  local rest host path
  case "${url}" in
    *://*)
      rest="${url#*://}"
      rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      ;;
    *@*:*)
      rest="${url#*@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
    *) return 1 ;;
  esac
  host="${host%%:*}"
  path="${path%/}"
  path="${path%.git}"
  [[ -n "${path}" && "${path}" != "${rest}" ]] || return 1
  case "${host}" in
    gitlab.com | altssh.gitlab.com) printf 'gitlab %s\n' "${path}" ;;
    github.com | ssh.github.com) printf 'github %s\n' "${path}" ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Print the path of a mirrored repository on the other forge
# @arg $1 string Mirrors of dynet, a JSON file with `.mirrors`
# @arg $2 string Forge the path is on, `gitlab` or `github`
# @arg $3 string Path of the repository there
# @stdout Its path on the other forge
# @exitcode 0 The repository is mirrored
# @exitcode 1 It is not, or the mirrors cannot be read
#######################################
function mirror::counterpart {
  local mirrors forge path
  dybatpho::expect_args mirrors forge path -- "$@"
  local other
  case "${forge}" in
    gitlab) other="github" ;;
    github) other="gitlab" ;;
    *) return 1 ;;
  esac
  [[ -r "${mirrors}" ]] || return 1
  local found
  # The path goes in as data, never as part of the expression.
  found="$(MIRROR_PATH="${path}" yq -p=json -o=yaml -r \
    ".mirrors[] | select(.${forge} == strenv(MIRROR_PATH)) | .${other}" "${mirrors}")" \
    || return 1
  found="${found%%$'\n'*}"
  [[ -n "${found}" ]] || return 1
  printf '%s\n' "${found}"
}

#######################################
# @description Point a remote of a checkout at a URL, adding the remote when
# it is missing. A remote already on that repository, in whatever form, is
# left as it is.
# @arg $1 string Checkout
# @arg $2 string Remote
# @arg $3 string URL
#######################################
function __mirror_set_remote {
  local dir name url
  dybatpho::expect_args dir name url -- "$@"
  local current="" wanted current_repo=""
  # The URL as configured: `git remote get-url` would show the rules of dynet.
  current="$(git -C "${dir}" config --get "remote.${name}.url")" || current=""
  if [[ -z "${current}" ]]; then
    git -C "${dir}" remote add "${name}" "${url}"
    dybatpho::info "Added remote ${name}: ${url}"
    return 0
  fi
  wanted="$(mirror::parse_url "${url}")"
  current_repo="$(mirror::parse_url "${current}")" || current_repo=""
  if [[ "${current_repo}" != "${wanted}" ]]; then
    git -C "${dir}" remote set-url "${name}" "${url}"
    dybatpho::info "Moved remote ${name} from ${current} to ${url}"
  fi
}

#######################################
# @description Give a checkout of a mirrored repository `origin` on GitLab
# and `gh` on GitHub, from the URL of its `origin`, which may name either.
# Both keep the protocol of that URL; dynet switches it as the network needs.
# @arg $1 string Mirrors of dynet, a JSON file with `.mirrors`
# @arg $2 string Checkout
# @exitcode 0 The checkout has both remotes
# @exitcode 1 It has no `origin`, or the repository is not mirrored
#######################################
function mirror::set_remotes {
  local mirrors dir
  dybatpho::expect_args mirrors dir -- "$@"
  local url parsed forge path other
  url="$(git -C "${dir}" config --get remote.origin.url)" || return 1
  parsed="$(mirror::parse_url "${url}")" || return 1
  read -r forge path <<< "${parsed}"
  other="$(mirror::counterpart "${mirrors}" "${forge}" "${path}")" || return 1

  local gitlab_path="${path}" github_path="${other}"
  if [[ "${forge}" == "github" ]]; then
    gitlab_path="${other}"
    github_path="${path}"
  fi
  local gitlab="git@gitlab.com:" github="git@github.com:"
  if [[ "${url}" == https://* ]]; then
    gitlab="https://gitlab.com/"
    github="https://github.com/"
  fi
  __mirror_set_remote "${dir}" origin "${gitlab}${gitlab_path}.git"
  __mirror_set_remote "${dir}" gh "${github}${github_path}.git"
}
