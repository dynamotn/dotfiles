function __caran_fzf_git_branch_switch -d 'Switch to a local or remote branch'
    set -l picked (__caran_fzf_git_branch_pick); or return 1
    set -l branch $picked[1]
    set -l worktree $picked[2]

    # A branch checked out in another worktree cannot be switched to here:
    # go to that worktree instead
    if test -n "$worktree"; and test "$worktree" != (git rev-parse --show-toplevel)
        cd $worktree
    else
        git switch $branch
    end

    commandline -f repaint
end
