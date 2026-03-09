function ssh --description "SSH to machine" --argument server
    __caran_ssh_config_dir
    and __caran_terminal_workspace_rename_window ssh-$server
    and command ssh -t $argv
    set ssh_status $status
    __caran_terminal_workspace_undo_rename_window
    return $ssh_status
end
