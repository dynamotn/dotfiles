function __caran_fzf_git_commit_search -d 'Show list commits by tree graph'
    __fish_is_git_repository; or return 1
    set -l preview_cmd "--preview-window=right:wrap --preview='fish -c \"__fzf_complete_preview {} \'{1}\' \'Commit: \"{3..}\"\'\"'"
    eval "$FZF_GIT_COMMIT_SEARCH_COMMAND | "(__fzfcmd) $preview_cmd "-m $FZF_DEFAULT_OPTS --ansi" | read -l select

    if not test -z "$select"
        set -l hash (echo $select | awk '{ print $1 }')
        echo "$hash"
    end

    commandline -f repaint
end
