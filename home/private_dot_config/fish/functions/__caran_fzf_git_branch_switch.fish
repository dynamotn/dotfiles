function __caran_fzf_git_branch_switch -d 'Switch to a local or remote branch'
    __fish_is_git_repository; or return 1
    # A remote branch is listed without its remote: `git switch` then creates
    # the local branch tracking it.
    begin
        git for-each-ref --format='%(refname:short)' refs/heads
        git for-each-ref --format='%(refname:lstrip=3)' refs/remotes
    end | string match -v HEAD | awk '!seen[$0]++' \
        | eval (__fzfcmd) "--prompt='branch> ' --preview='git log --color --oneline -20 {} --'" | read -l branch

    if test -n "$branch"
        git switch $branch
    end

    commandline -f repaint
end
