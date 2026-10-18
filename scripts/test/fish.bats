setup() {
  load test_helper
  # A HOME of its own: the stand-ins below go into its ~/.local/bin
  setup_dotfiles_test_env
  # dyshellint disable=SC2154 DOTFILES_DIR is set by test_helper
  FISH_DIR="${DOTFILES_DIR}/home/private_dot_config/fish"
  command -v fish > /dev/null || skip "fish is not installed"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run fish code with none of the user's configuration loaded
function _fish {
  local code
  dybatpho::expect_args code -- "$@"
  fish --no-config -c "${code}"
}

# Run fish code that autoloads the functions of this configuration. Extra
# arguments land in $argv, so no quoting of them can leak into the code.
# fish_history is set because `fish -c` otherwise runs without a history.
function _fishf {
  fish_history=fish fish --no-config -c "set -p fish_function_path '${FISH_DIR}/functions'
    function __fzfcmd; echo fzf; end
    $1" "${@:2}"
}

# The same in an interactive shell, where conf.d hooks and `commandline` run.
# No multiplexer, kitty or SSH session of the machine running the suite leaks in.
function _fishi {
  env -u ZELLIJ -u SSH_TTY -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON TERM=dumb fish_history=fish \
    fish --no-config -i -c "set -p fish_function_path '${FISH_DIR}/functions'
    function __fzfcmd; echo fzf; end
    $1" "${@:2}"
}

# Whether the history hook stores a command line
function _stored {
  local cmdline
  dybatpho::expect_args cmdline -- "$@"
  # dyshellint disable=SC2016 fish code, expanded by fish rather than here
  _fishf 'fish_should_add_to_history $argv[1]' "${cmdline}"
}

# Write a stand-in for a command into the test HOME's ~/.local/bin
function _stub {
  local name body
  dybatpho::expect_args name body -- "$@"
  printf '#!/bin/sh\n%s\n' "${body}" > "${HOME}/.local/bin/${name}"
  chmod +x "${HOME}/.local/bin/${name}"
}

# A stand-in for a command that records its arguments, one call per line
function _stub_recorder {
  local name
  dybatpho::expect_args name -- "$@"
  # dyshellint disable=SC2154 BATS_TEST_TMPDIR is set by bats
  _stub "${name}" "echo \"${name} \$*\" >> '${BATS_TEST_TMPDIR}/calls'"
}

# A stand-in for fzf: the Nth call picks the first input line holding the Nth
# line of the picks file
function _stub_fzf {
  printf '%s\n' "$@" > "${BATS_TEST_TMPDIR}/picks"
  _stub fzf "input=\$(cat)
n=\$((\$(cat '${BATS_TEST_TMPDIR}/fzf.n' 2>/dev/null || echo 0) + 1))
echo \"\${n}\" > '${BATS_TEST_TMPDIR}/fzf.n'
printf '%s\n' \"\${input}\" | grep -F -m1 -- \"\$(sed -n \"\${n}p\" '${BATS_TEST_TMPDIR}/picks')\""
}

# Fill the fish history of the test HOME, one command per argument
function _history {
  local file="${HOME}/.local/share/fish/fish_history" cmd
  dybatpho::ensure_dir "$(dirname "${file}")" > /dev/null
  for cmd in "$@"; do
    printf -- '- cmd: %s\n  when: 1700000000\n' "${cmd}" >> "${file}"
  done
}

# A repository with one commit, as the current directory of the test
function _git_repo {
  REPO="${BATS_TEST_TMPDIR}/repo"
  dybatpho::ensure_dir "${REPO}" > /dev/null
  # dyshellint disable=BSG062 test_helper, loaded in setup, unsets GIT_DIR and its kin
  git -C "${REPO}" init -q -b main
  git -C "${REPO}" config user.name Test
  git -C "${REPO}" config user.email test@example.com
  printf 'seed\n' > "${REPO}/seed.txt"
  git -C "${REPO}" add seed.txt
  git -C "${REPO}" commit -q -m seed
}

# Every fish source the configuration holds, in FISH_FILES
function _all_fish_files {
  FISH_FILES=("${FISH_DIR}"/conf.d/*.fish "${FISH_DIR}"/functions/*.fish
    "${FISH_DIR}"/completions/*.fish "${FISH_DIR}/setup.fish")
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "every fish file parses" {
  local failures=() file
  _all_fish_files
  for file in "${FISH_FILES[@]}"; do
    fish --no-execute "${file}" 2> /dev/null || failures+=("${file}")
  done
  ((${#failures[@]} == 0)) || fail "$(printf '%s: syntax error\n' "${failures[@]}")"
}

@test "every fish file is formatted by fish_indent" {
  command -v fish_indent > /dev/null || skip "fish_indent is not installed"
  _all_fish_files
  run fish_indent --check "${FISH_FILES[@]}"
  assert_success
}

@test "the rendered config.fish parses and is formatted" {
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  local rendered="${BATS_TEST_TMPDIR}/config.fish"
  render_template home/private_dot_config/fish/config.fish.tmpl "${rendered}"
  run fish --no-execute "${rendered}"
  assert_success
  if command -v fish_indent > /dev/null; then
    run fish_indent --check "${rendered}"
    assert_success
  fi
}

@test "fish_should_add_to_history stores an ordinary command" {
  run _stored 'git status'
  assert_success
  run _stored 'kubectl get secret my-app -o yaml'
  assert_success
  # dyshellint disable=SC2016 the command line is fish text, not expanded here
  run _stored 'echo $GITHUB_TOKEN | wc -c'
  assert_success
}

@test "fish_should_add_to_history keeps a command typed after a space out" {
  run _stored ' git status'
  assert_failure
}

@test "fish_should_add_to_history keeps a credential assignment out" {
  run _stored 'GH_TOKEN=abc gh pr list'
  assert_failure
  run _stored 'export AWS_SECRET_ACCESS_KEY=abc'
  assert_failure
  run _stored 'set -gx GitLab_Token abc'
  assert_failure
}

@test "fish_should_add_to_history keeps a credential flag out" {
  run _stored 'mysql --password=hunter2 db'
  assert_failure
  run _stored 'vault login --token abc'
  assert_failure
}

@test "fish_should_add_to_history stores a flag with no value after it" {
  run _stored 'gh auth login --with-token < token.txt'
  assert_success
}

@test "fish_should_add_to_history keeps headers, URL passwords and token shapes out" {
  run _stored 'curl -H "Authorization: Bearer abc" https://example.com'
  assert_failure
  run _stored 'git clone https://user:pass@example.com/repo.git'
  assert_failure
  run _stored "git remote add o https://$(printf 'ghp_%s' 'aaaaaaaaaaaaaaaaaaaaaaaa')@github.com/x/y"
  assert_failure
}

@test "shortcuts are abbreviations that expand to the full command" {
  run _fish "source '${FISH_DIR}/conf.d/git.fish'
    source '${FISH_DIR}/conf.d/kubectl.fish'
    abbr --show | string match -e -- 'grh'
    abbr --show | string match -e -- ' kk '"
  assert_success
  assert_line --partial "grh 'git reset --hard'"
  assert_line --partial "kk 'kubectl apply -k'"
}

@test "the replacement aliases stay out of a non-interactive shell" {
  # A stand-in for procs, so the alias would be defined if the guard were missing
  printf '#!/bin/sh\n' > "${HOME}/.local/bin/procs"
  chmod +x "${HOME}/.local/bin/procs"

  run _fish "source '${FISH_DIR}/conf.d/zzz_alternative.fish'; functions -q ps"
  assert_failure
}

# Sets up a repository with a pre-commit config and a prek stand-in that
# records each call
function _prek_repo {
  printf '#!/bin/sh\necho "$*" >> "%s/prek.calls"\n' "${BATS_TEST_TMPDIR}" > "${HOME}/.local/bin/prek"
  chmod +x "${HOME}/.local/bin/prek"
  dybatpho::ensure_dir "${BATS_TEST_TMPDIR}/repo" > /dev/null
  # dyshellint disable=BSG062 test_helper, loaded in setup, unsets GIT_DIR and its kin
  git -C "${BATS_TEST_TMPDIR}/repo" init -q
  touch "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"
}

# Enter the repository from an interactive shell, where the PWD hooks run
function _cd_into_repo {
  _fishi "source '${FISH_DIR}/conf.d/auto.fish'
    cd '${BATS_TEST_TMPDIR}/repo'" > /dev/null 2>&1
}

@test "entering a repository installs the prek shim" {
  _prek_repo
  _cd_into_repo
  assert_file_contains "${BATS_TEST_TMPDIR}/prek.calls" 'install --hook-type pre-commit'
}

@test "entering a repository leaves an installed prek shim alone" {
  _prek_repo
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.git/hooks"
  printf '#!/bin/sh\nexec prek hook-impl\n' > "${BATS_TEST_TMPDIR}/repo/.git/hooks/pre-commit"
  _cd_into_repo
  assert_file_not_exists "${BATS_TEST_TMPDIR}/prek.calls"
}

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------

@test "fish_should_add_to_history takes the patterns of this machine" {
  run _fishf 'set -g history_secret_patterns "corp_[a-z]+"
    fish_should_add_to_history "deploy corp_abc"'
  assert_failure
}

@test "fish_should_add_to_history says when it keeps a command out" {
  run _fishi 'fish_should_add_to_history "GH_TOKEN=abc gh pr list"'
  assert_failure
  assert_output --partial 'not saved to history'
  run _fishi 'set -g history_secret_notice 0; fish_should_add_to_history "GH_TOKEN=abc gh pr list"'
  refute_output --partial 'not saved to history'
}

@test "history_scrub lists the credentials masked and deletes nothing on a dry run" {
  _history 'git status' 'mysql --password=hunter2 db'
  run _fishi 'history_scrub --dry-run'
  assert_success
  assert_output --partial 'mysql [REDACTED] db'
  assert_output --partial '1 history entries carry a credential'
  refute_output --partial 'hunter2'
  assert_file_contains "${HOME}/.local/share/fish/fish_history" 'hunter2'
}

@test "history_scrub deletes the entries carrying a credential, and only those" {
  _history 'git status' 'mysql --password=hunter2 db'
  run _fishi 'history_scrub --yes'
  assert_success
  assert_output --partial 'Deleted 1 entries'
  assert_file_not_contains "${HOME}/.local/share/fish/fish_history" 'hunter2'
  assert_file_contains "${HOME}/.local/share/fish/fish_history" 'git status'
}

@test "history_scrub deletes nothing when the answer is no" {
  _history 'mysql --password=hunter2 db'
  run _fishi 'history_scrub' <<< 'n'
  assert_failure
  assert_file_contains "${HOME}/.local/share/fish/fish_history" 'hunter2'
}

# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------

# Run the end-of-command hook as if a command had taken that many milliseconds
function _command_ended {
  local duration cmdline
  dybatpho::expect_args duration cmdline -- "$@"
  _stub_recorder osascript
  _stub_recorder notify-send
  _fishi "source '${FISH_DIR}/conf.d/notify.fish'
    ${PRELUDE:-}
    set CMD_DURATION ${duration}
    emit fish_postexec \$argv[1]" "${cmdline}"
}

@test "a long command sends a notification" {
  _command_ended 70000 'make build'
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'Done make build · 70s'
}

@test "a short command, an ignored program or an ignored directory sends none" {
  _command_ended 1000 'make build'
  _command_ended 70000 'nvim notes.md'
  PRELUDE="set -g notify_long_command_ignore_dirs '${BATS_TEST_TMPDIR}*'; cd '${BATS_TEST_TMPDIR}'" \
    _command_ended 70000 'make build'
  assert_file_not_exists "${BATS_TEST_TMPDIR}/calls"
}

@test "a notification shows a command carrying a credential by its program only" {
  _command_ended 70000 'curl -H "Authorization: Bearer abc" https://example.com'
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'Done curl · 70s'
  assert_file_not_contains "${BATS_TEST_TMPDIR}/calls" 'Bearer'
}

@test "a focused kitty window gets no notification, an unfocused one does" {
  command -v jq > /dev/null || skip "jq is not installed"
  local focused='[{"is_focused": true, "tabs": [{"is_focused": true, "windows": [{"is_focused": true}]}]}]'
  local unfocused='[{"is_focused": false, "tabs": [{"is_focused": true, "windows": [{"is_focused": true}]}]}]'
  local kitty='set -gx KITTY_WINDOW_ID 1; set -gx KITTY_LISTEN_ON unix:/tmp/kitty-test'

  _stub kitten "echo '${focused}'"
  PRELUDE="${kitty}" _command_ended 70000 'make build'
  assert_file_not_exists "${BATS_TEST_TMPDIR}/calls"

  _stub kitten "echo '${unfocused}'"
  PRELUDE="${kitty}" _command_ended 70000 'make build'
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'Done make build'
}

@test "notify_me sends to Telegram with the token kept out of the arguments" {
  _stub_recorder osascript
  _stub_recorder notify-send
  _stub curl "cat > '${BATS_TEST_TMPDIR}/curl.stdin'; echo \"curl \$*\" >> '${BATS_TEST_TMPDIR}/calls'"
  run _fishi 'set -gx NOTIFY_TELEGRAM_BOT_TOKEN test-token-value
    set -gx NOTIFY_TELEGRAM_CHAT_ID 42
    notify_me false'
  assert_failure 1

  # The request runs in the background
  local _
  for _ in $(seq 50); do
    grep -q '^curl' "${BATS_TEST_TMPDIR}/calls" 2> /dev/null && break
    sleep 0.1
  done
  assert_file_contains "${BATS_TEST_TMPDIR}/curl.stdin" 'bottest-token-value/sendMessage'
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'chat_id=42'
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'Failed (1): false'
  assert_file_not_contains "${BATS_TEST_TMPDIR}/calls" 'test-token-value'
}

# ---------------------------------------------------------------------------
# Pickers
# ---------------------------------------------------------------------------

function _stub_kubectl {
  _stub kubectl "case \"\$1 \$2\" in
  'get pods') printf 'web-1   1/1   Running   0   1d\napi-2   1/1   Running   0   1d\n' ;;
  *) echo \"kubectl \$*\" >> '${BATS_TEST_TMPDIR}/calls' ;;
esac"
}

@test "fkpod runs the action picked on the pod picked" {
  _stub_kubectl
  _stub_fzf web-1 describe
  _fishf '__caran_fzf_kube_pod_action' > /dev/null 2>&1 || true
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'kubectl describe pod web-1'
}

@test "fkpod deletes nothing unless the deletion is confirmed" {
  _stub_kubectl
  _stub_fzf api-2 delete
  _fishf '__caran_fzf_kube_pod_action' <<< 'n' > /dev/null 2>&1 || true
  assert_file_not_exists "${BATS_TEST_TMPDIR}/calls"
}

@test "fgb switches to the branch picked" {
  _git_repo
  git -C "${REPO}" branch feature
  _stub_fzf feature
  run _fishf "cd '${REPO}'; __caran_fzf_git_branch_switch 2>/dev/null; git branch --show-current"
  assert_line feature
}

@test "fgb goes to the worktree of a branch checked out there" {
  _git_repo
  git -C "${REPO}" worktree add -q "${BATS_TEST_TMPDIR}/wt" -b other
  _stub_fzf other
  run _fishf "cd '${REPO}'; __caran_fzf_git_branch_switch 2>/dev/null; pwd"
  assert_output --partial '/wt'
  run git -C "${REPO}" branch --show-current
  assert_output main
}

@test "fgst applies the stash picked" {
  _git_repo
  printf 'changed\n' > "${REPO}/seed.txt"
  git -C "${REPO}" stash -q
  _stub_fzf WIP apply
  _fishf "cd '${REPO}'; __caran_fzf_git_stash_action" > /dev/null 2>&1 || true
  assert_file_contains "${REPO}/seed.txt" 'changed'
}

@test "fdx opens a shell in the container picked" {
  _stub docker "case \"\$1\" in
  ps) printf 'web\tnginx\tUp 1 hour\ndb\tpostgres\tUp 1 hour\n' ;;
  *) echo \"docker \$*\" >> '${BATS_TEST_TMPDIR}/calls' ;;
esac"
  _stub_fzf db
  _fishf '__caran_fzf_docker_exec' > /dev/null 2>&1 || true
  assert_file_contains "${BATS_TEST_TMPDIR}/calls" 'docker exec -it db sh -c'
}

@test "ctrl-o sequences are bound in emacs and vi insert mode" {
  run _fishi "source '${FISH_DIR}/conf.d/auto.fish'
    bind ctrl-o,b
    fish_vi_key_bindings
    bind -M insert ctrl-o,p"
  assert_output --partial '__caran_fzf_insert __caran_fzf_git_branch_pick'
  assert_output --partial '__caran_fzf_insert __caran_fzf_kube_pod_pick'
}

# ---------------------------------------------------------------------------
# Abbreviations
# ---------------------------------------------------------------------------

@test "... expands to the parent directories" {
  run _fishf '__caran_abbr_up_dirs ...; __caran_abbr_up_dirs ..../src'
  assert_line --index 0 '../..'
  assert_line --index 1 '../../../src'
}

@test "!! and !\$ expand to the previous command and its last argument" {
  _history 'cp a "b c"'
  run _fishi '__caran_abbr_last_command; __caran_abbr_last_argument'
  assert_line --index 0 'cp a "b c"'
  assert_line --index 1 "'b c'"
}

@test "a short subcommand expands only as the first argument" {
  run _fishf "source '${FISH_DIR}/conf.d/abbr.fish'
    function commandline; echo git; end
    __caran_abbr_subcommand co
    function commandline; printf '%s\n' git add; end
    __caran_abbr_subcommand co
    function commandline; echo kubectl; end
    __caran_abbr_subcommand x"
  assert_line --index 0 checkout
  assert_line --index 1 co
  assert_line --index 2 'exec -it'
}

# A project directory holding a .fish-abbr
function _project {
  PROJECT="${BATS_TEST_TMPDIR}/project"
  dybatpho::ensure_dir "${PROJECT}/sub" > /dev/null
  printf '# a comment\nhi echo hello\n' > "${PROJECT}/.fish-abbr"
}

@test "an untrusted .fish-abbr is not loaded" {
  _project
  run _fishi "source '${FISH_DIR}/conf.d/dir_abbr.fish'
    cd '${PROJECT}/sub'
    abbr --query hi; and echo loaded; or echo absent"
  assert_output --partial 'is not trusted'
  assert_line absent
}

@test "a trusted .fish-abbr is loaded below it and erased outside" {
  _project
  run _fishi "source '${FISH_DIR}/conf.d/dir_abbr.fish'
    cd '${PROJECT}'
    dir_abbr trust -y > /dev/null
    cd sub
    abbr --query hi; and echo loaded
    cd '${BATS_TEST_TMPDIR}'
    abbr --query hi; or echo erased"
  assert_line loaded
  assert_line erased
}

@test "an edited .fish-abbr needs trust again" {
  _project
  _fishi "source '${FISH_DIR}/conf.d/dir_abbr.fish'; cd '${PROJECT}'; dir_abbr trust -y" > /dev/null 2>&1
  printf 'hi echo changed\n' > "${PROJECT}/.fish-abbr"
  run _fishi "source '${FISH_DIR}/conf.d/dir_abbr.fish'
    cd '${PROJECT}'
    abbr --query hi; and echo loaded; or echo absent"
  assert_output --partial 'is not trusted'
  assert_line absent
}

@test "a .fish-abbr never takes over an abbreviation defined elsewhere" {
  _project
  run _fishi "abbr -a hi 'echo global'
    source '${FISH_DIR}/conf.d/dir_abbr.fish'
    cd '${PROJECT}'
    dir_abbr trust -y > /dev/null
    abbr --show | string match -e -- ' hi '"
  assert_output --partial "'echo global'"
  refute_output --partial "'echo hello'"
}

# ---------------------------------------------------------------------------
# Listing on cd
# ---------------------------------------------------------------------------

@test "entering a repository shows its README and a git summary, once" {
  _git_repo
  printf '# Title\n\nFirst line\nSecond line\nThird line\n' > "${REPO}/README.md"
  mkdir "${REPO}/sub"
  run _fishi "source '${FISH_DIR}/conf.d/auto.fish'
    cd '${REPO}'
    cd sub"
  assert_output --partial '# Title'
  assert_output --partial 'Second line'
  refute_output --partial 'Third line'
  assert_output --partial 'main · 1 changed'
  local summaries
  summaries="$(grep -c 'main ·' <<< "${output}" || true)"
  ((summaries == 1)) || fail "the git summary showed ${summaries} times"
}

@test "the README and the git summary can be turned off" {
  _git_repo
  printf '# Title\n' > "${REPO}/README.md"
  run _fishi "set -g auto_ls_readme_lines 0; set -g auto_ls_git_summary 0
    source '${FISH_DIR}/conf.d/auto.fish'
    cd '${REPO}'"
  refute_output --partial '# Title'
  refute_output --partial 'main ·'
}
