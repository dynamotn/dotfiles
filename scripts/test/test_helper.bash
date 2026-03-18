DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DYBATPHO_DIR="${DOTFILES_DIR}/scripts/lib/dybatpho"
DOTFILES_REAL_HOME="${HOME}"
DOTFILES_REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
. "${DYBATPHO_DIR}/init.sh"

bats_require_minimum_version 1.5.0

function setup_dotfiles_test_env {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  mkdir -p "${HOME}/.config/dytoy" "${HOME}/.config/chezmoi" "${HOME}/.local/bin"
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
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME}" \
      chezmoi execute-template < "${DOTFILES_DIR}/${relative_path}" > "${output_path}"
  )
  chmod +x "${output_path}"
}

function write_tools_yaml {
  cat > "${HOME}/.config/dytoy/tools.yaml"
}
