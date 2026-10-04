DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# A git hook runs the suite with the repository it fires in exported as
# `GIT_DIR`, `GIT_INDEX_FILE` and friends. Left in place, every git call a test
# makes reaches that repository instead of the one it names. These are the
# names `git rev-parse --local-env-vars` lists.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE \
  GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS \
  GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR
DYBATPHO_DIR="${DOTFILES_DIR}/scripts/lib/dybatpho"
DOTFILES_REAL_HOME="${HOME}"
. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
# Bats runs each test in its own process, where the module registry
# `dybatpho::load` reads cannot follow (Bash cannot export an associative
# array), so every module the libraries under test load is named here.
. "${DYBATPHO_DIR}/init.sh" --modules cli network archive json array pkg screen privilege
DOTFILES_REAL_XDG_CONFIG_HOME="$(dybatpho::xdg_config_dir)"

bats_require_minimum_version 1.5.0

function setup_dotfiles_test_env {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  dybatpho::ensure_dir "$(dybatpho::xdg_config_dir dytoy)" > /dev/null
  dybatpho::ensure_dir "$(dybatpho::xdg_config_dir chezmoi)" > /dev/null
  dybatpho::ensure_dir "${HOME}/.local/bin" > /dev/null
  export PATH="${HOME}/.local/bin:${PATH}"
  export DRY_RUN="false"
  export LOG_LEVEL="debug"
  export ONLY_NOT_INSTALLED="true"
  export ONLY_ESSENTIAL="false"
  export LIST_CONTENTS="false"
}

function render_template {
  local relative_path output_path
  dybatpho::expect_args relative_path output_path -- "$@"
  # `--source` renders against the checkout under test. Without it chezmoi takes
  # the source directory from the real configuration, so from a worktree the
  # rendered paths, and the libraries the script sources, were the main
  # checkout's.
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME}" \
      chezmoi execute-template --source "${DOTFILES_DIR}" \
      < "${DOTFILES_DIR}/${relative_path}" > "${output_path}"
  )
  chmod +x "${output_path}"
}

function write_tools_yaml {
  cat > "${HOME}/.config/dytoy/tools.yaml"
}
