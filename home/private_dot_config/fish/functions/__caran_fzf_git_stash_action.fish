function __caran_fzf_git_stash_action -d 'Pick a stash, then apply, show or drop it'
    __fish_is_git_repository; or return 1
    git stash list --format='%gd%x09%H%x09%s' \
        | __caran_fzf --prompt='stash> ' --delimiter='\t' --with-nth=1,3 \
        --preview='git stash show -p --color {2}' \
        | read -l select
    test -n "$select"; or return 1
    # Kept by hash: the stash@{n} of a stash moves as others come and go
    set -l sha (string split -f2 \t -- $select)

    printf '%s\n' apply show drop | __caran_fzf --prompt='stash> ' | read -l action
    switch "$action"
        case apply
            git stash apply $sha
        case show
            git stash show -p $sha
        case drop
            # `stash drop` takes a reflog entry, not a hash: find it again now
            set -l ref (git stash list --format='%gd %H' | string replace -rf "^(\S+) $sha\$" '$1')
            test -n "$ref"; or return 1
            __caran_confirm "Drop $ref ("(string split -f3 \t -- $select)")?"; and git stash drop $ref
    end

    commandline -f repaint
end
