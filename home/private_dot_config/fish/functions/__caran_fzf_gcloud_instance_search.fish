function __caran_fzf_gcloud_instance_search -d "Search Gcloud instance"
    eval "$FZF_GCLOUD_INSTANCE_SEARCH_COMMAND | "(__fzfcmd) "-m $FZF_DEFAULT_OPTS --ansi" | read -l select

    if not test -z "$select"
        set -l instance (echo $select | awk '{ print $1 }')
        echo "$instance"
    end

    commandline -f repaint
end
