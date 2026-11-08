DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Bats records a stack trace on every command its DEBUG trap sees, which made
# sourcing the libraries cost about a second per test. Their failures still
# point at the line of the test that called them.
bats_add_debug_exclude_path "${DOTFILES_DIR}/scripts/lib/"
DYBATPHO_DIR="${DOTFILES_DIR}/scripts/lib/dybatpho"
DOTFILES_REAL_HOME="${HOME}"
. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
# Bats runs each test in its own process, where the module registry
# `dybatpho::load` reads cannot follow (Bash cannot export an associative
# array), so every module the libraries under test load is named here.
. "${DYBATPHO_DIR}/init.sh" --modules cli network archive json array pkg screen privilege lock cache testing
# A git hook runs the suite with its repository exported as `GIT_DIR` and
# friends; left in place, every git call a test makes would reach it.
dybatpho::test_unset_git_env
DOTFILES_REAL_XDG_CONFIG_HOME="$(dybatpho::xdg_config_dir)"

bats_require_minimum_version 1.5.0

function setup_dotfiles_test_env {
  # Every XDG dir too: left pointing at the real home, fish reads (and
  # history_scrub deletes from) the real history.
  dybatpho::test_home
  dybatpho::ensure_dir "$(dybatpho::xdg_config_dir dytoy)" > /dev/null
  dybatpho::ensure_dir "$(dybatpho::xdg_config_dir chezmoi)" > /dev/null
  export DRY_RUN="false"
  export LOG_LEVEL="debug"
  export ONLY_NOT_INSTALLED="true"
  export ONLY_ESSENTIAL="false"
  export LIST_CONTENTS="false"
  # The real zellij and kitty are on PATH: no test may open a pane or a tab in
  # the user's session. dyai_zellij.bats and dyai_hunk.bats unset it.
  export DYAI_VIEWS="off"
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
