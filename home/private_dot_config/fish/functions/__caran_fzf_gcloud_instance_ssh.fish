function __caran_fzf_gcloud_instance_ssh -d "SSH to Gcloud instance"
    eval "$FZF_GCLOUD_ACTIVE_INSTANCE_SEARCH_COMMAND | "(__fzfcmd) "-m $FZF_DEFAULT_OPTS --ansi" | read -l select

    if test -z "$select"
        return 1
    end

    set -l instance (echo $select | awk '{ print $1 }')
    set -l zone (echo $select | awk '{ print $2 }')

    __caran_terminal_workspace_rename_window ssh-$instance
    set -l ssh_command (string unescape "gcloud compute ssh --zone '$zone' '$instance' --")
    if ! test -z (eval "$ssh_command command -v zellij")
        eval "$ssh_command zellij"
    else if ! test -z (eval "$ssh_command command -v tmux")
        eval "$ssh_command tmux"
    else
        eval "$ssh_command"
    end
    __caran_terminal_workspace_recover_name_window
end
