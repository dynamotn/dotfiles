function __caran_fzf_gcloud_instance_search -d "Search Gcloud instance"
    gcloud compute instances list | tail -n +2 | __caran_fzf --ansi | read -l select

    if test -n "$select"
        string split -f1 ' ' -- $select
    end

    commandline -f repaint
end
