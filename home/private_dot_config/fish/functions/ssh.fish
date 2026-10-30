function ssh --description "SSH to machine"
    __caran_ssh_config_dir; or return

    # The host is the first argument that is not an option or its value. With
    # -N, -T or -f nobody types into the session: leave it alone, a forced
    # tty would break it.
    set -l server
    set -l has_command false
    set -l background false
    set -l skip false
    for arg in $argv
        if $skip
            set skip false
        else if test -n "$server"
            set has_command true
        else if string match -qr -- '^-.' $arg
            # Short flags may be bundled, as in -fN or -p22
            set -l flags (string sub -s 2 -- $arg | string split '')
            for i in (seq (count $flags))
                string match -qr -- '^[NTf]$' $flags[$i]; and set background true
                if string match -qr -- '^[bcDEeFIiJLlmOopQRSWw]$' $flags[$i]
                    test $i -eq (count $flags); and set skip true
                    break
                end
            end
        else
            set server $arg
        end
    end

    if $background; or test -z "$server"
        command ssh $argv
        return
    end

    # A command wants a tty (zellij, tmux) only when one is there to give; a
    # captured `ssh host command -v tmux` must not get one
    set -l tty
    isatty 0; and isatty 1; and set tty -t
    if $has_command
        command ssh $tty $argv
        return
    end

    __caran_terminal_workspace_rename_window ssh-$server
    command ssh $tty $argv
    set -l ssh_status $status
    __caran_terminal_workspace_undo_rename_window
    return $ssh_status
end
