setup() {
  load test_helper
  SCHEMA_DIR="${DOTFILES_DIR}/schemas/secrets"
  DATA_DIR="${DOTFILES_DIR}/secrets/data"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function _require_ys {
  command -v ys &> /dev/null || skip "ys not found – install with: cargo install yaml-schema"
}

# Validate a YAML file against a schema, or skip if the file does not exist.
# Usage: _validate <schema_file> <yaml_file>
function _validate {
  local schema="${1}" yaml="${2}"
  if [ ! -f "${yaml}" ]; then
    skip "secrets file not found (not decrypted): ${yaml}"
  fi
  ys -f "${schema}" "${yaml}"
}

# ---------------------------------------------------------------------------
# common.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/common.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/common.schema.yaml" "${DATA_DIR}/enterprise-F1/common.yaml"
}

@test "secrets/enterprise-T1/common.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/common.schema.yaml" "${DATA_DIR}/enterprise-T1/common.yaml"
}

@test "secrets/enterprise-ZOO/common.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/common.schema.yaml" "${DATA_DIR}/enterprise-ZOO/common.yaml"
}

@test "secrets/enterprise-U3T/common.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/common.schema.yaml" "${DATA_DIR}/enterprise-U3T/common.yaml"
}

# ---------------------------------------------------------------------------
# git.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/git.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/git.schema.yaml" "${DATA_DIR}/enterprise-F1/git.yaml"
}

@test "secrets/enterprise-T1/git.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/git.schema.yaml" "${DATA_DIR}/enterprise-T1/git.yaml"
}

@test "secrets/enterprise-ZOO/git.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/git.schema.yaml" "${DATA_DIR}/enterprise-ZOO/git.yaml"
}

@test "secrets/enterprise-U3T/git.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/git.schema.yaml" "${DATA_DIR}/enterprise-U3T/git.yaml"
}

# ---------------------------------------------------------------------------
# docker.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/docker.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/docker.schema.yaml" "${DATA_DIR}/enterprise-F1/docker.yaml"
}

@test "secrets/personal/docker.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/docker.schema.yaml" "${DATA_DIR}/personal/docker.yaml"
}

# ---------------------------------------------------------------------------
# firefox.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/firefox.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/firefox.schema.yaml" "${DATA_DIR}/enterprise-F1/firefox.yaml"
}

# ---------------------------------------------------------------------------
# jira.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/jira.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/jira.schema.yaml" "${DATA_DIR}/enterprise-F1/jira.yaml"
}

# ---------------------------------------------------------------------------
# k8s.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/k8s.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/k8s.schema.yaml" "${DATA_DIR}/enterprise-F1/k8s.yaml"
}

@test "secrets/personal/k8s.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/k8s.schema.yaml" "${DATA_DIR}/personal/k8s.yaml"
}

# ---------------------------------------------------------------------------
# projekt.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/projekt.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/projekt.schema.yaml" "${DATA_DIR}/enterprise-F1/projekt.yaml"
}

@test "secrets/enterprise-T1/projekt.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/projekt.schema.yaml" "${DATA_DIR}/enterprise-T1/projekt.yaml"
}

@test "secrets/enterprise-ZOO/projekt.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/projekt.schema.yaml" "${DATA_DIR}/enterprise-ZOO/projekt.yaml"
}

# ---------------------------------------------------------------------------
# rbw.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/rbw.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/rbw.schema.yaml" "${DATA_DIR}/enterprise-F1/rbw.yaml"
}

@test "secrets/personal/rbw.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/rbw.schema.yaml" "${DATA_DIR}/personal/rbw.yaml"
}

# ---------------------------------------------------------------------------
# ssh.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/ssh.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/ssh.schema.yaml" "${DATA_DIR}/enterprise-F1/ssh.yaml"
}

@test "secrets/personal/ssh.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/ssh.schema.yaml" "${DATA_DIR}/personal/ssh.yaml"
}

# ---------------------------------------------------------------------------
# wifi.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/wifi.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/wifi.schema.yaml" "${DATA_DIR}/enterprise-F1/wifi.yaml"
}

# ---------------------------------------------------------------------------
# wol.yaml
# ---------------------------------------------------------------------------

@test "secrets/personal/wol.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/wol.schema.yaml" "${DATA_DIR}/personal/wol.yaml"
}

# ---------------------------------------------------------------------------
# ssl.yaml
# ---------------------------------------------------------------------------

@test "secrets/enterprise-F1/ssl.yaml conforms to schema" {
  _require_ys
  _validate "${SCHEMA_DIR}/ssl.schema.yaml" "${DATA_DIR}/enterprise-F1/ssl.yaml"
}
