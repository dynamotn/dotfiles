# dyshellint disable=SC2154 BATS_TEST_TMPDIR comes from bats
# dyshellint disable=BSG062 test_helper unsets GIT_DIR and its kin
setup() {
  load test_helper
  setup_dotfiles_test_env

  local name
  for name in strip_agent_credit commit_message worktree_submodules worktree_cleanup; do
    render_template "home/private_dot_config/git/scripts/executable_${name}.sh.tmpl" \
      "${BATS_TEST_TMPDIR}/${name}.sh"
  done
  NULL_REF="0000000000000000000000000000000000000000"

  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global user.name "Test"
  git config --global user.email "test@example.com"
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
  git config --global protocol.file.allow always

  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "${REPO}"
  git -C "${REPO}" commit -q --allow-empty -m "seed"
  cd "${REPO}" || return 1
}

@test "strip_agent_credit drops agent trailers and keeps the human ones" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  cat > "${msg}" << 'EOF'
feat: add a thing

Body line.

Co-authored-by: Jane Doe <jane@example.com>
Co-Authored-By: Claude <noreply@anthropic.com>
Assisted-by: Codex
Claude-Session: https://claude.ai/code/session_123
🤖 Generated with [Claude Code](https://claude.com/claude-code)
# ------------------------ >8 ------------------------
+Co-Authored-By: Claude in the diff stays
EOF

  run bash "${BATS_TEST_TMPDIR}/strip_agent_credit.sh" "${msg}"
  assert_success
  assert_output --partial "Dropped the agent attribution lines"
  run cat "${msg}"
  assert_line "Co-authored-by: Jane Doe <jane@example.com>"
  assert_line "+Co-Authored-By: Claude in the diff stays"
  refute_line --partial "noreply@anthropic.com"
  refute_line --partial "Assisted-by"
  refute_line --partial "Claude-Session"
  refute_line --partial "Generated with"
}

@test "strip_agent_credit leaves a clean message untouched" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  printf 'fix: a bug\n\nThe why.\n' > "${msg}"
  cp "${msg}" "${msg}.orig"

  run bash "${BATS_TEST_TMPDIR}/strip_agent_credit.sh" "${msg}"
  assert_success
  assert_output ""
  run diff "${msg}.orig" "${msg}"
  assert_success
}

@test "worktree_submodules checks out what the main checkout has, minus the opted out" {
  local name
  for name in wanted other; do
    git init -q "${BATS_TEST_TMPDIR}/${name}"
    git -C "${BATS_TEST_TMPDIR}/${name}" commit -q --allow-empty -m "${name}"
    git -C "${REPO}" submodule add -q "${BATS_TEST_TMPDIR}/${name}" "${name}"
  done
  git -C "${BATS_TEST_TMPDIR}/wanted" submodule add -q "${BATS_TEST_TMPDIR}/other" nested
  git -C "${BATS_TEST_TMPDIR}/wanted" commit -q -m "nested"
  git -C wanted pull -q
  git -C wanted submodule update -q --init
  git add wanted
  git config -f .gitmodules submodule.other.worktreeInit false
  git add .gitmodules
  git commit -q -m "submodules"
  git worktree add -q .worktrees/task -b task

  cd .worktrees/task || return 1
  local head
  head="$(git rev-parse HEAD)"
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${NULL_REF}" "${head}" 1
  assert_success
  assert_exists wanted/.git
  assert_exists wanted/nested/.git
  assert_not_exists other/.git
}

@test "worktree_submodules does nothing in a plain clone or a branch switch" {
  git config -f .gitmodules submodule.x.path x

  local head
  head="$(git rev-parse HEAD)"
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${NULL_REF}" "${head}" 1
  assert_success
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${head}" "${head}" 1
  assert_success
  assert_output ""
}

@test "worktree_cleanup removes the merged worktree and keeps its branch" {
  git worktree add -q .worktrees/finished -b finished
  git -C .worktrees/finished commit -q --allow-empty -m "work"
  git worktree add -q .worktrees/fresh -b fresh
  git worktree add -q .worktrees/dirty -b dirty finished
  git -C .worktrees/dirty commit -q --allow-empty -m "dirty work"
  touch .worktrees/dirty/untracked
  git merge -q --ff-only dirty

  run bash "${BATS_TEST_TMPDIR}/worktree_cleanup.sh" 0
  assert_success
  assert_output --partial "/.worktrees/dirty: it still holds"
  assert_not_exists .worktrees/finished
  assert_exists .worktrees/fresh
  assert_exists .worktrees/dirty/untracked
  run git branch --list finished
  assert_output --partial "finished"
}

@test "commit_message refuses a long subject and passes a short one" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  printf 'feat: %s\n' "$(printf 'x%.0s' {1..70})" > "${msg}"
  run bash "${BATS_TEST_TMPDIR}/commit_message.sh" "${msg}"
  assert_failure
  assert_output --partial "the limit is 72"

  printf 'fix: a bug\n' > "${msg}"
  run bash "${BATS_TEST_TMPDIR}/commit_message.sh" "${msg}"
  assert_success
}

# A stand-in age that shows whether the textconv got as far as decrypting
function _decrypt_setup {
  render_template "home/private_dot_config/git/scripts/decrypt_chezmoi.sh.tmpl" \
    "${BATS_TEST_TMPDIR}/decrypt.sh"
  printf '#!/bin/sh\necho PLAINTEXT\n' > "${HOME}/.local/bin/age"
  chmod +x "${HOME}/.local/bin/age"
  : > "${BATS_TEST_TMPDIR}/secret.age"
}

@test "decrypt_chezmoi prints a placeholder, not the secret, without a terminal" {
  _decrypt_setup
  # setsid drops the controlling terminal, as an agent's shell has none
  run setsid -w bash "${BATS_TEST_TMPDIR}/decrypt.sh" _normal personal "${BATS_TEST_TMPDIR}/secret.age"
  assert_success
  assert_output '<encrypted: decrypting a diff needs a terminal>'
}

# Run the driver on a terminal of its own, where the given keys are typed.
function _decrypt_on_terminal {
  command -v python3 > /dev/null || skip "python3 gives the terminal"
  run python3 -I - "$1" "${BATS_TEST_TMPDIR}/decrypt.sh" "${BATS_TEST_TMPDIR}/secret.age" << 'PY'
import os, pty, sys
keys, script, secret = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", script, "_normal", "personal", secret])
os.write(fd, keys.encode())
out = b""
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace"))
PY
}

@test "decrypt_chezmoi decrypts once y is typed on the terminal" {
  _decrypt_setup
  _decrypt_on_terminal y
  assert_output --partial PLAINTEXT
}

@test "decrypt_chezmoi keeps the secret when the terminal does not answer y" {
  _decrypt_setup
  _decrypt_on_terminal n
  refute_output --partial PLAINTEXT
  assert_output --partial '<encrypted: decrypting was not confirmed>'
}

@test "sdiff gives the diff of the directory it was called from, with the status of git diff" {
  render_template "home/private_dot_config/git/scripts/sdiff.sh.tmpl" "${BATS_TEST_TMPDIR}/sdiff.sh"
  local repo="${BATS_TEST_TMPDIR}/sdiff-repo"
  git init -q -b main "${repo}"
  mkdir "${repo}/sub"
  printf 'one\n' > "${repo}/sub/file"
  git -C "${repo}" add sub/file
  git -C "${repo}" -c user.name=tester -c user.email=tester@example.com commit -q -m init
  printf 'two\n' > "${repo}/sub/file"
  cd "${repo}" || fail "no repository"
  # As git runs an alias: from the top, with the caller's directory in GIT_PREFIX.
  GIT_PREFIX="sub/" run "${BASH}" "${BATS_TEST_TMPDIR}/sdiff.sh" --exit-code -- file
  assert_failure 1
  assert_output --partial '+two'
  GIT_PREFIX="sub/" run "${BASH}" "${BATS_TEST_TMPDIR}/sdiff.sh" --exit-code -- missing
  assert_success
  assert_output ""
}
