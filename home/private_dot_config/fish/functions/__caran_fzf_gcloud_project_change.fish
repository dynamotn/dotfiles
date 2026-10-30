function __caran_fzf_gcloud_project_change -d "Change project of GCP"
    gcloud projects list --format='table[no-heading](projectId,name)' | __caran_fzf --ansi | read -l select

    if test -n "$select"
        gcloud config set project (string split -f1 ' ' -- $select)
    end

    commandline -f repaint
end
