# dyshellint disable=SC2154 DOTFILES_DIR, DOTFILES_REAL_* and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  RULES="home/.chezmoitemplates/wm/rules.yaml.tmpl"
}

# Render the template $1 into $2, with the chezmoi data overridden by $3.
function _render {
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi execute-template --source "${DOTFILES_DIR}" --override-data "${3}" \
      --file "${DOTFILES_DIR}/${1}" > "${2}"
  )
}

# Fail, naming $1, when the file $2 holds one line twice.
function _no_duplicates {
  local sorted="${2}.sorted" dups
  sort "${2}" > "${sorted}"
  dups="$(uniq -d "${sorted}")"
  [[ -z "${dups}" ]] || fail "${1} binds twice: ${dups}"
}

@test "no window manager binds one key twice, at home or at the office" {
  local place out="${BATS_TEST_TMPDIR}" data
  for place in home office; do
    data="{\"place\":\"${place}\",\"guiWinManager\":\"O\",\"hasSound\":true}"
    _render home/private_dot_config/niri/niri/binding.kdl.tmpl "${out}/niri.kdl" "${data}"
    grep -oE '^  [^ /][^ ]*' "${out}/niri.kdl" > "${out}/niri.keys"
    _no_duplicates niri "${out}/niri.keys"
    _render home/private_dot_config/hypr/hyprland/binding.lua.tmpl "${out}/hypr.lua" "${data}"
    grep -oE '^(hl\.bind|exec)\("[^"]+"' "${out}/hypr.lua" > "${out}/hypr.keys"
    _no_duplicates Hyprland "${out}/hypr.keys"
    _render home/private_dot_config/aerospace/aerospace.toml.tmpl "${out}/aerospace.toml" "${data}"
    # A key repeated in one TOML table does not parse.
    yq -p toml -o json '.mode.main.binding' "${out}/aerospace.toml" > /dev/null
    _render home/private_dot_hammerspoon/init.lua.tmpl "${out}/init.lua" "${data}"
    grep -oE "^hs\.hotkey\.bind\(\{[^}]*\}, '[^']+'" "${out}/init.lua" > "${out}/hs.keys"
    _no_duplicates Hammerspoon "${out}/hs.keys"
  done
}

@test "OmniWM lists each hotkey id once and gives no two ids one key" {
  local out="${BATS_TEST_TMPDIR}/settings.toml"
  _render home/private_dot_config/omniwm/settings.toml.tmpl "${out}" '{"place":"home","guiWinManager":"O"}'
  yq -p toml -o tsv '.hotkeys[] | [.id]' "${out}" > "${out}.ids"
  _no_duplicates "OmniWM ids" "${out}.ids"
  yq -p toml -o tsv '.hotkeys[] | select(.binding != "Unassigned") | [.binding]' "${out}" > "${out}.keys"
  _no_duplicates "OmniWM keys" "${out}.keys"
}

@test "every action of the rules is bound by some window manager" {
  local out="${BATS_TEST_TMPDIR}" data='{"place":"home","guiWinManager":"O","hasSound":true}'
  local consumer action
  _render "${RULES}" "${out}/rules.yaml" "${data}"
  : > "${out}/consumers"
  for consumer in home/private_dot_config/niri/niri/binding.kdl.tmpl \
    home/private_dot_config/hypr/hyprland/binding.lua.tmpl \
    home/private_dot_config/aerospace/aerospace.toml.tmpl \
    home/private_dot_hammerspoon/init.lua.tmpl \
    home/private_dot_config/omniwm/settings.toml.tmpl; do
    cat "${DOTFILES_DIR}/${consumer}" >> "${out}/consumers"
  done
  yq '.bindings[].action' "${out}/rules.yaml" > "${out}/actions"
  while IFS= read -r action; do
    grep -qF "\"${action}\"" "${out}/consumers" || fail "no window manager binds ${action}"
  done < "${out}/actions"
}
