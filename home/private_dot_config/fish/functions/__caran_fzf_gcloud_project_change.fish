function __caran_fzf_gcloud_project_change -d "Change project of GCP"
    eval "$FZF_GCLOUD_PROJECT_SEARCH_COMMAND | "(__fzfcmd) "-m $FZF_DEFAULT_OPTS --ansi" | read -l select

    if not test -z "$select"
        set -l project_id (echo $select | awk '{ print $1 }')
        eval "$FZF_GCLOUD_PROJECT_SWITCH_COMMAND"
    end

    commandline -f repaint
end
