#!/usr/bin/env bash
# @file cron.sh
# @brief Library `cron` for managing the user crontab
# @description Library `cron` for managing the user crontab: the dotfiles own
# named blocks of it, between `# BEGIN dotfiles:<name>` and
# `# END dotfiles:<name>` markers, and leave every other line as it was.
#######################################
# @description Replace a named block of the user crontab with the lines read
# from stdin, or remove the block when stdin is empty. The crontab is only
# written when its content changes.
# @arg $1 string Name of the block
# @stdin Crontab lines of the block
#######################################
function cron::set_block {
  local name
  dybatpho::expect_args name -- "$@"
  local begin="# BEGIN dotfiles:${name}" end="# END dotfiles:${name}"
  local block current error
  block="$(cat)"
  # `crontab -l` fails both for a user without a crontab and for a real error;
  # only the first is an empty crontab. Writing after the second would wipe it.
  if ! dybatpho::try current error -- crontab -l; then
    [[ "${error}" == *"no crontab"* ]] \
      || dybatpho::die "Cannot read the crontab: ${error}"
    current=""
  fi

  local wanted
  wanted="$(
    if [[ -n "${current}" ]]; then
      awk -v b="${begin}" -v e="${end}" \
        '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' \
        <<< "${current}"
    fi
    if [[ -n "${block}" ]]; then
      printf '%s\n%s\n%s\n' "${begin}" "${block}" "${end}"
    fi
  )"
  [[ "${wanted}" == "${current}" ]] && return 0
  printf '%s\n' "${wanted}" | dybatpho::dry_run -- crontab -
}
