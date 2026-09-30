# fish ships a thorough git completion, but a git.fish in the user completion
# directory shadows it instead of adding to it. So load the shipped one first,
# then repair the cases it hands to plain file completion and teach it the
# `!sh` aliases from ~/.config/git/config.
set -l shipped (status get-file completions/git.fish 2>/dev/null)
if set -q shipped[1]
    # fish >= 4.1 carries its completions inside the binary
    printf '%s\n' $shipped | source
else
    set -l self (status filename)
    for dir in $fish_complete_path
        test -f $dir/git.fish; or continue
        test "$dir/git.fish" != "$self"; or continue
        source $dir/git.fish
        break
    end
end

# Everything below builds on the helpers of the shipped completion.
functions -q __fish_git_using_command; or exit 0

# Positional arguments already given to the current subcommand, so a completion
# can tell `git archive <tree-ish>` from the paths that follow it. Global
# options such as `-C <dir>` are parsed away, the subcommand itself is kept as
# the first element, and options of the subcommand are dropped.
function __caran_git_args --description 'Positional arguments of the current git subcommand'
    set -l tokens (commandline -xpc)
    set -e tokens[1]
    argparse -s (__fish_git_global_optspecs) -- $tokens 2>/dev/null; or return
    for token in $argv
        string match -q -- '-*' $token; and continue
        echo $token
    end
end

function __caran_git_tracked_files --description 'Files git already tracks'
    __fish_git ls-files --exclude-standard 2>/dev/null
end

function __caran_git_unmerged_files --description 'Files left with conflicts'
    __fish_git diff --name-only --diff-filter=U --relative 2>/dev/null
end

function __caran_git_assume_unchanged_files --description 'Files hidden with --assume-unchanged'
    __fish_git ls-files -v 2>/dev/null | string replace --regex --filter '^[a-z] ' ''
end

function __caran_git_skip_worktree_files --description 'Files hidden with --skip-worktree'
    __fish_git ls-files -v 2>/dev/null | string replace --regex --filter '^S ' ''
end

# Only a submodule that points at another commit has something for git to act
# on: new files or edits inside it change nothing in the superproject. With
# --cached, list the submodules whose new commit is already staged instead.
function __caran_git_modified_submodules --description 'Submodules checked out at another commit'
    argparse cached -- $argv; or return
    set -l diff_opts --raw --ignore-submodules=dirty
    set -q _flag_cached; and set -a diff_opts --cached
    # The paths come from the top of the repository; write them relative to the
    # current directory, the way the shipped file completions do.
    set -l prefix (__fish_git rev-parse --show-prefix 2>/dev/null)
    set -l cdup (__fish_git rev-parse --show-cdup 2>/dev/null)
    for submodule in (__fish_git diff $diff_opts 2>/dev/null \
            | string replace --regex --filter '^:\d+ 160000 \S+ \S+ \S+\t' '')
        if test -n "$prefix"; and string match -q -- "$prefix*" $submodule
            string replace -- $prefix '' $submodule
        else
            echo $cdup$submodule
        end
    end
end

##
## Cases the shipped completion leaves to plain file completion
##

# Commands that only ever touch tracked files, never untracked ones
for subcommand in rm blame annotate ls-files update-index check-attr
    complete -f -c git -n "__fish_git_using_command $subcommand" \
        -n 'not __fish_git_contains_opt cached' \
        -a '(__caran_git_tracked_files)' -d 'Tracked file'
end

# History commands take a pathspec, which is pointless for an untracked file
for subcommand in log shortlog whatchanged grep
    complete -f -c git -n "__fish_git_using_command $subcommand" \
        -a '(__caran_git_tracked_files)' -d 'Tracked file'
end

# `git clean` removes exactly the untracked files, and the ignored ones with -x/-X
complete -f -c git -n '__fish_git_using_command clean' -a '(__fish_git_files untracked)'
complete -f -c git -n '__fish_git_using_command clean' -n '__fish_git_contains_opt -s x -s X' \
    -a '(__fish_git_files ignored)'

# The shipped file lists run `git status --ignore-submodules=all`, so no command
# ever offers a submodule whose pointer moved. Add it back where it counts:
# `add`, `diff` and `commit` for a new commit not staged yet, and `diff
# --cached`, `commit`, `reset` and `restore --staged` for one already staged.
# `checkout`, `restore` and `stash` are left out: without --recurse-submodules
# they can't move a submodule back, so offering one would only mislead.
complete -f -c git -n '__fish_git_using_command add commit' \
    -a '(__caran_git_modified_submodules)' -d 'Modified submodule'
complete -f -c git -n '__fish_git_using_command diff' -n 'not __fish_git_contains_opt cached staged' \
    -a '(__caran_git_modified_submodules)' -d 'Modified submodule'
complete -f -c git -n '__fish_git_using_command diff' -n '__fish_git_contains_opt cached staged' \
    -a '(__caran_git_modified_submodules --cached)' -d 'Staged submodule'
complete -f -c git -n '__fish_git_using_command commit reset' \
    -a '(__caran_git_modified_submodules --cached)' -d 'Staged submodule'
complete -f -c git -n '__fish_git_using_command restore' -n '__fish_git_contains_opt -s S staged' \
    -a '(__caran_git_modified_submodules --cached)' -d 'Staged submodule'

# `git mergetool` only makes sense on the files that are still conflicted
complete -f -c git -n '__fish_git_using_command mergetool' \
    -a '(__caran_git_unmerged_files)' -d 'Unmerged file'

# `git archive <tree-ish> [path...]`
complete -f -c git -n '__fish_git_using_command archive' \
    -n 'test (count (__caran_git_args)) -eq 1' -a '(__fish_git_refs)'
complete -f -c git -n '__fish_git_using_command archive' \
    -n 'test (count (__caran_git_args)) -gt 1' -a '(__caran_git_tracked_files)' -d 'Tracked file'

# `git tag <name> [commit]`: the name is new, so nothing to offer for it, and
# the second argument is a commit
complete -f -c git -n '__fish_git_using_command tag' \
    -n 'test (count (__caran_git_args)) -eq 1'
complete -f -c git -n '__fish_git_using_command tag' \
    -n 'not __fish_git_contains_opt -s d -s v -s l delete verify list' \
    -n 'test (count (__caran_git_args)) -gt 1' -a '(__fish_git_commits)'

# Plumbing that reads refs, not paths
for subcommand in symbolic-ref update-ref show-ref for-each-ref name-rev rev-list replace diff-tree
    complete -f -c git -n "__fish_git_using_command $subcommand" -a '(__fish_git_refs)'
end

# `git init [dir]` and `git clone <repo|dir> [dir]` want directories
complete -f -c git -n '__fish_git_using_command init' -a '(__fish_complete_directories)'
complete -f -c git -n '__fish_git_using_command clone' -a '(__fish_complete_directories)'

# Every submodule subcommand that takes paths, beyond the two fish knows about
complete -f -c git -n '__fish_git_using_command submodule' \
    -n '__fish_seen_subcommand_from update init sync absorbgitdirs set-branch set-url' \
    -n 'not contains -- -- (commandline -xpc)' \
    -a '(__fish_git_submodules)' -d Submodule

##
## Aliases from ~/.config/git/config
##

# fish maps an alias to the first git-looking word of its body, which for a
# `!_() { ... }` wrapper is never the right one: `stash-rename` would complete
# like `rev-parse`, `snapshot` like `stash`. Drop the mapping of every shell
# alias and let the rules below speak for them; an alias that really is a git
# command with extra options, such as `graph = log --graph`, keeps its mapping.
git config -z --get-regexp '^alias\.' 2>/dev/null | while read -lz key value
    string match -q -- '!*' $value; or continue
    set -e __fish_git_alias_(string replace 'alias.' '' -- $key | string escape --style=var)
end

# None of the shell aliases takes a bare path, so keep plain file completion out
# of the way. What each one does accept comes right after.
for alias in main snapshot stash-rename find-source find-message find-branch \
    stop-track track keep-forever stop-keep-forever root up conflicts \
    delete-dangling delete-merged submodule-clean update-main mirror unshallow wt
    complete -f -c git -n "__fish_git_using_command $alias"
end

# `git stash-rename <stash> <message>`
complete -f -c git -n '__fish_git_using_command stash-rename' \
    -n 'test (count (__caran_git_args)) -eq 1' -a '(__fish_git_complete_stashes)'
complete -f -c git -n '__fish_git_using_command stash-rename' \
    -n 'test (count (__caran_git_args)) -gt 1'

# `git find-branch <commit>`
complete -f -c git -n '__fish_git_using_command find-branch' -a '(__fish_git_commits)'

# The update-index wrappers, each on the files that are in the state it changes
complete -f -c git -n '__fish_git_using_command stop-track' \
    -a '(__caran_git_tracked_files)' -d 'Tracked file'
complete -f -c git -n '__fish_git_using_command track' \
    -a '(__caran_git_assume_unchanged_files)' -d 'Assumed unchanged'
complete -f -c git -n '__fish_git_using_command keep-forever' \
    -a '(__caran_git_tracked_files)' -d 'Tracked file'
complete -f -c git -n '__fish_git_using_command stop-keep-forever' \
    -a '(__caran_git_skip_worktree_files)' -d 'Kept forever'

# `git unshallow <remote>` and `git mirror [gitlab remote] [github remote]`
complete -f -c git -n '__fish_git_using_command unshallow' -a '(__fish_git_remotes)' -d Remote
complete -f -c git -n '__fish_git_using_command mirror' \
    -n 'test (count (__caran_git_args)) -le 2' -a '(__fish_git_remotes)' -d Remote

# `git gen-patch <file>` writes the patch, so a plain file argument is right
complete -F -c git -n '__fish_git_using_command gen-patch'
