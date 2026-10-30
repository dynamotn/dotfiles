# Usage: __caran_remote_workspace SESSION RUNNER...
# RUNNER runs a command on the machine, as `ssh host` or `gcloud compute ssh i --`
function __caran_remote_workspace -d "Attach to zellij or tmux on a remote machine, else a plain shell" -a session
    set -e argv[1]

    if test -n "$($argv command -v zellij)"
        # A bare `zellij a` refuses to choose once several sessions are live,
        # so take the newest live one (zellij lists newest first)
        if test -z "$session"
            set session ($argv zellij ls -n 2>/dev/null | string match -v '*EXITED*' | string split -f1 ' ')[1]
        end
        # The remote fish runs this non-interactively, so its config.fish
        # never points ZELLIJ_CONFIG_FILE at ssh.kdl (Alt x, no rail)
        set -l config "\$HOME/.config/zellij/ssh.kdl"
        $argv zellij --config $config a $session
        or $argv zellij --config $config
    else if test -n "$($argv command -v tmux)"
        set -l attach_argv
        set -l new_argv
        if test -n "$session"
            set attach_argv -t $session
            set new_argv -s $session
        end
        $argv tmux at $attach_argv
        or $argv tmux new $new_argv
    else
        $argv
    end
end
