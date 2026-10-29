#!/usr/bin/env bats
# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/mirror.sh"
  MIRRORS="${BATS_TEST_TMPDIR}/mirrors.json"
  cat > "${MIRRORS}" << 'EOF'
{
  "mirrors": [
    {"gitlab": "dynamo-config/dotfiles", "github": "dynamotn/dotfiles"},
    {"gitlab": "dynamo-config/dotfiles-secrets", "github": "dynamotn/dotfiles-secrets"}
  ]
}
EOF
  REPO="${BATS_TEST_TMPDIR}/repo"
  # dyshellint disable=BSG062 test_helper, loaded above, unsets GIT_DIR and its kin
  git init -q "${REPO}"
}

# Print the remotes of the test checkout as configured, one `name url` a line,
# in the order they were added.
function _remotes {
  local remotes key url
  remotes="$(git -C "${REPO}" config --get-regexp '^remote\..*\.url$')"
  while read -r key url; do
    key="${key#remote.}"
    printf '%s %s\n' "${key%.url}" "${url}"
  done <<< "${remotes}"
}

@test "mirror::parse_url reads every form of a GitLab or GitHub URL" {
  local url
  for url in git@gitlab.com:dynamo-config/dotfiles.git \
    git@altssh.gitlab.com:dynamo-config/dotfiles \
    ssh://git@altssh.gitlab.com:443/dynamo-config/dotfiles.git \
    https://gitlab.com/dynamo-config/dotfiles.git \
    https://gitlab.com/dynamo-config/dotfiles/; do
    run mirror::parse_url "${url}"
    assert_success
    assert_output "gitlab dynamo-config/dotfiles"
  done
  for url in git@ssh.github.com:dynamotn/dotfiles.git https://github.com/dynamotn/dotfiles; do
    run mirror::parse_url "${url}"
    assert_output "github dynamotn/dotfiles"
  done
}

@test "mirror::parse_url rejects other hosts and URLs without a path" {
  local url
  for url in git@example.com:someone/tool.git https://gitlab.com/ /srv/git/tool.git \
    file:///srv/git/tool.git; do
    run mirror::parse_url "${url}"
    assert_failure
  done
}

@test "mirror::counterpart finds the path on the other forge" {
  run mirror::counterpart "${MIRRORS}" gitlab dynamo-config/dotfiles
  assert_success
  assert_output "dynamotn/dotfiles"
  run mirror::counterpart "${MIRRORS}" github dynamotn/dotfiles-secrets
  assert_output "dynamo-config/dotfiles-secrets"
}

@test "mirror::counterpart fails for a repository that is not mirrored" {
  run mirror::counterpart "${MIRRORS}" gitlab dynamo-config/dotfiles-other
  assert_failure
  run mirror::counterpart "${MIRRORS}" gitlab 'x") | .gitlab'
  assert_failure
  run mirror::counterpart "${BATS_TEST_TMPDIR}/missing.json" gitlab dynamo-config/dotfiles
  assert_failure
}

@test "mirror::set_remotes adds gh to a clone from GitLab" {
  git -C "${REPO}" remote add origin git@gitlab.com:dynamo-config/dotfiles
  run mirror::set_remotes "${MIRRORS}" "${REPO}"
  assert_success
  run _remotes
  assert_output "origin git@gitlab.com:dynamo-config/dotfiles
gh git@github.com:dynamotn/dotfiles.git"
  # A second run finds nothing to change.
  run mirror::set_remotes "${MIRRORS}" "${REPO}"
  assert_success
  assert_output ""
}

@test "mirror::set_remotes moves a clone from GitHub to origin on GitLab" {
  git -C "${REPO}" remote add origin https://github.com/dynamotn/dotfiles-secrets.git
  mirror::set_remotes "${MIRRORS}" "${REPO}"
  run _remotes
  assert_output "origin https://gitlab.com/dynamo-config/dotfiles-secrets.git
gh https://github.com/dynamotn/dotfiles-secrets.git"
}

@test "mirror::set_remotes points a stale gh at the mirror" {
  git -C "${REPO}" remote add origin git@gitlab.com:dynamo-config/dotfiles.git
  git -C "${REPO}" remote add gh git@github.com:someone/fork.git
  mirror::set_remotes "${MIRRORS}" "${REPO}"
  run git -C "${REPO}" config --get remote.gh.url
  assert_output "git@github.com:dynamotn/dotfiles.git"
}

@test "the post-checkout hook gives a clone of a mirrored repository gh" {
  local bare="${BATS_TEST_TMPDIR}/dotfiles.git"
  local clone="${BATS_TEST_TMPDIR}/clone" hook="${BATS_TEST_TMPDIR}/checkout_changes.sh"
  render_template home/private_dot_config/git/scripts/executable_checkout_changes.sh.tmpl "${hook}"
  sed -i "s|'${DOTFILES_REAL_HOME}/.config/dynet/mirrors.json'|'${MIRRORS}'|" "${hook}"
  git init -q --bare -b main "${bare}"
  git -C "${REPO}" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
  git -C "${REPO}" push -q "${bare}" HEAD:main
  # The clone keeps the GitLab URL in its config; only the transport is local.
  git -c "url.${bare}.insteadOf=git@gitlab.com:dynamo-config/dotfiles.git" \
    -c hook.checkout-changes.event=post-checkout -c "hook.checkout-changes.command=${hook}" \
    clone -q git@gitlab.com:dynamo-config/dotfiles.git "${clone}"
  run git -C "${clone}" config --get remote.gh.url
  assert_output "git@github.com:dynamotn/dotfiles.git"
  run git -C "${clone}" config --get remote.origin.url
  assert_output "git@gitlab.com:dynamo-config/dotfiles.git"
}

@test "mirror::set_remotes leaves a repository that is not mirrored alone" {
  git -C "${REPO}" remote add origin git@gitlab.com:someone/tool.git
  run mirror::set_remotes "${MIRRORS}" "${REPO}"
  assert_failure
  run _remotes
  assert_output "origin git@gitlab.com:someone/tool.git"
  git -C "${REPO}" remote remove origin
  run mirror::set_remotes "${MIRRORS}" "${REPO}"
  assert_failure
}
