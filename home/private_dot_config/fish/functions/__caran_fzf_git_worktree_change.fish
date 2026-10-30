function __caran_fzf_git_worktree_change -d 'Go to a worktree of the repository'
    __fish_is_git_repository; or return 1
    # The porcelain format keeps a path holding spaces whole
    git worktree list --porcelain | string replace -rf '^worktree ' '' \
        | __caran_fzf --prompt='worktree> ' | read -l worktree

    if test -n "$worktree"
        cd $worktree
    end

    commandline -f repaint
end
