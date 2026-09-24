#!/usr/bin/env bash
# @file dycrypt.sh
# @brief Encrypt and decrypt the secrets of this repository with a single age identity
# @description Two storage layouts share one pair of operations:
#
#   - *data*: plaintext and ciphertext live side by side under
#     `secrets/data/<identity>/`, and the ciphertext is the plaintext plus
#     `.age`;
#   - *target*: the plaintext is a live file somewhere under `$HOME` or `/`,
#     and the ciphertext goes into the chezmoi source tree at the path
#     `chezmoi_attrs::source_path` derives for it.
#
# Both layouts resolve to the same (plaintext, ciphertext) pair, so `encrypt`
# and `decrypt` are the same code walked in opposite directions.
#
# @env DYCRYPT_DOTFILES_DIR string Root of this repository, set by the caller

# @env DYCRYPT_AGE_EXT string Extension of an age encrypted file
DYCRYPT_AGE_EXT=".age"

#######################################
# @description Fail unless `age` and the repository root are usable
#######################################
function dycrypt::check_prerequisites {
  dybatpho::is command age > /dev/null \
    || dybatpho::die "age is not installed, cannot work with encrypted secrets"
  dybatpho::is dir "${DYCRYPT_DOTFILES_DIR:-}" \
    || dybatpho::die "DYCRYPT_DOTFILES_DIR '${DYCRYPT_DOTFILES_DIR:-}' is not a directory"
}

#######################################
# @description Check that an identity can be used as a path component
# @arg $1 string Identity type
# @exitcode 1 The identity is empty or holds a character that could escape its folder
#######################################
function dycrypt::validate_identity {
  local identity
  dybatpho::expect_args identity -- "$@"
  if [[ ! "${identity}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    dybatpho::error "Identity type '${identity}' must only hold letters, digits, '.', '_' or '-'"
    return 1
  fi
}

#######################################
# @description Resolve the age identity key of an identity type
# @arg $1 string Variable name that receives the key path
# @arg $2 string Identity type
#######################################
function dycrypt::identity_key {
  local key_var identity
  dybatpho::expect_args key_var identity -- "$@"
  dycrypt::validate_identity "${identity}" || dybatpho::die "Invalid identity type"

  # Named apart from anything a caller may pass as `$1`: this function writes
  # into the caller's scope, and a local of the same name would swallow it.
  local __key_path
  __key_path="$(dybatpho::path_join "${HOME}" ".config" "chezmoi" "${identity}.key")"
  dybatpho::is file "${__key_path}" \
    || dybatpho::die "No age identity for '${identity}', expected a key at ${__key_path}"
  # Reports a key readable by anyone else before it is used, not after.
  dybatpho::secret_check_permission "${__key_path}"
  printf -v "${key_var}" '%s' "${__key_path}"
}

#######################################
# @description Resolve the plaintext and ciphertext paths of a secret
# @arg $1 string Variable name that receives the plaintext path
# @arg $2 string Variable name that receives the ciphertext path
# @arg $3 string Identity type
# @arg $4 string File name
# @arg $5 string Folder of the plaintext, or `data` for the secrets data store
# @arg $6 string Attributes of the chezmoi source file, separated by `,`
#######################################
function dycrypt::resolve_paths {
  local plain_var cipher_var identity filename folder attributes
  dybatpho::expect_args plain_var cipher_var identity filename folder attributes -- "$@"
  dycrypt::validate_identity "${identity}" || dybatpho::die "Invalid identity type"

  filename="$(dybatpho::trim "${filename}")"
  [[ -n "${filename}" ]] || dybatpho::die "File name must not be empty"

  # See `dycrypt::identity_key` for why these names are not `plain` and `cipher`.
  local __plain_path __cipher_path __source_path
  if [[ "${folder}" == "data" ]]; then
    __plain_path="$(dybatpho::path_join "${DYCRYPT_DOTFILES_DIR}" "secrets" "data" "${identity}" "${filename}")"
    __cipher_path="${__plain_path}${DYCRYPT_AGE_EXT}"
  else
    __plain_path="$(dybatpho::path_join "${folder}" "${filename}")"
    chezmoi_attrs::source_path __source_path "${__plain_path}" "${attributes:+${attributes},}encrypted" \
      || dybatpho::die "Cannot derive the chezmoi source path of ${__plain_path}"
    __cipher_path="$(dybatpho::path_join "${DYCRYPT_DOTFILES_DIR}" "${__source_path}${DYCRYPT_AGE_EXT}")"
  fi

  printf -v "${plain_var}" '%s' "${__plain_path}"
  printf -v "${cipher_var}" '%s' "${__cipher_path}"
}

#######################################
# @description Check whether a ciphertext already holds the plaintext
# @arg $1 string Plaintext path
# @arg $2 string Ciphertext path
# @arg $3 string Identity key path
# @exitcode 1 Either file is missing, the ciphertext cannot be read, or they differ
# @note Armored age output is not reproducible, so the ciphertext has to be
#   decrypted to be compared. A ciphertext that cannot be decrypted counts as
#   out of date: that is exactly the case a re-encryption repairs.
#######################################
function dycrypt::is_up_to_date {
  local plain cipher key
  dybatpho::expect_args plain cipher key -- "$@"

  dybatpho::is file "${plain}" || return 1
  dybatpho::is file "${cipher}" || return 1

  local temp_file
  dybatpho::create_temp temp_file ".tmp"
  if ! age -d -i "${key}" -o "${temp_file}" "${cipher}" 2> /dev/null; then
    dybatpho::debug "Cannot decrypt ${cipher} with ${key}, treating it as outdated"
    return 1
  fi
  cmp -s "${plain}" "${temp_file}"
}

#######################################
# @description Create the parent folder of a path, unless this is a dry run
# @arg $1 string Path whose parent folder is needed
#######################################
function dycrypt::ensure_parent {
  local path parent
  dybatpho::expect_args path -- "$@"
  parent="$(dybatpho::path_dirname "${path}")"
  if dybatpho::is true "${DRY_RUN:-false}"; then
    dybatpho::debug "Would create folder ${parent}"
  else
    dybatpho::ensure_dir "${parent}" > /dev/null
  fi
}

#######################################
# @description Encrypt a plaintext into its ciphertext
# @arg $1 string Identity type
# @arg $2 string Plaintext path
# @arg $3 string Ciphertext path
# @arg $4 string Re-encrypt even when the ciphertext is up to date
# @arg $5 string Remove the plaintext once it is encrypted
#######################################
function dycrypt::encrypt {
  local identity plain cipher force remove
  dybatpho::expect_args identity plain cipher force remove -- "$@"
  dycrypt::check_prerequisites

  local key
  dycrypt::identity_key key "${identity}"
  dybatpho::is file "${plain}" || dybatpho::die "Input ${plain} is not a file"

  if dybatpho::is false "${force}" && dycrypt::is_up_to_date "${plain}" "${cipher}" "${key}"; then
    dybatpho::debug "Output file ${cipher} is up to date"
  else
    dybatpho::info "Encrypt ${plain} to ${cipher}"
    dycrypt::ensure_parent "${cipher}"
    dybatpho::dry_run age -e -a -i "${key}" -o "${cipher}" "${plain}"
  fi

  if dybatpho::is true "${remove}"; then
    dybatpho::info "Remove input file ${plain}"
    dybatpho::dry_run rm -f "${plain}"
  fi
}

#######################################
# @description Decrypt a ciphertext back into its plaintext
# @arg $1 string Identity type
# @arg $2 string Ciphertext path
# @arg $3 string Plaintext path
# @arg $4 string Decrypt even when the plaintext already matches
# @note The plaintext is written with `umask 077`: it is a secret in the clear,
#   and it outlives this process.
#######################################
function dycrypt::decrypt {
  local identity cipher plain force
  dybatpho::expect_args identity cipher plain force -- "$@"
  dycrypt::check_prerequisites

  local key
  dycrypt::identity_key key "${identity}"
  dybatpho::is file "${cipher}" || dybatpho::die "Input ${cipher} is not a file"

  if dybatpho::is false "${force}" && dycrypt::is_up_to_date "${plain}" "${cipher}" "${key}"; then
    dybatpho::debug "Output file ${plain} is up to date"
    return 0
  fi
  dybatpho::info "Decrypt ${cipher} to ${plain}"
  dycrypt::ensure_parent "${plain}"
  (
    umask 077
    dybatpho::dry_run age -d -i "${key}" -o "${plain}" "${cipher}"
  )
}
