function __caran_fzf_gcloud_instance_ssh -d "SSH to Gcloud instance"
    gcloud compute instances list --filter='status=RUNNING' | tail -n +2 | __caran_fzf --ansi | read -l select
    test -n "$select"; or return 1

    set -l fields (string split -n ' ' -- $select)

    __caran_terminal_workspace_rename_window ssh-$fields[1]
    __caran_remote_workspace '' gcloud compute ssh --zone $fields[2] $fields[1] --
    __caran_terminal_workspace_undo_rename_window
end
