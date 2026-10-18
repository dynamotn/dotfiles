function __caran_fzf_git_branch_pick -d 'Pick a local or remote branch, and print its name and worktree'
    __fish_is_git_repository; or return 1
    # One line per branch: name, how far it is from its upstream, and the
    # worktree it is checked out in. A remote branch is listed without its
    # remote, and only when no local one has its name: `git switch` then
    # creates the local branch tracking it.
    begin
        git for-each-ref --format='%(refname:short)%09%(upstream:track)%09%(worktreepath)' refs/heads
        git for-each-ref --format='%(refname:lstrip=3)%09[remote]%09' refs/remotes
    end | string match -rv '^HEAD\t' | awk -F '\t' '!seen[$1]++' \
        | eval (__fzfcmd) "--prompt='branch> ' --delimiter='\t' \
            --preview='git log --color --oneline -20 {1} -- 2>/dev/null || git log --color --oneline -20 --remotes=\"*/{1}\"'" \
        | read -l select
    test -n "$select"; or return 1
    # The name, then the worktree path, empty when there is none
    set -l fields (string split \t -- $select)
    printf '%s\n' $fields[1] "$fields[3]"
end
