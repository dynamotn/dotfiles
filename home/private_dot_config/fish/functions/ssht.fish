function ssht --description "Run terminal workspace after ssh"
    argparse -N1 s= -- $argv
    or return
    set -l server $argv
    set -l session $_flag_s

    if test -n "$(ssh $server command -v zellij)"
        # A bare `zellij a` refuses to choose once several sessions are live,
        # so take the newest live one (zellij lists newest first)
        if test -z "$session"
            set session (ssh $server zellij ls -n 2>/dev/null | string match -v '*EXITED*' | string split -f1 ' ')[1]
        end
        # The remote fish runs this non-interactively, so its config.fish
        # never points ZELLIJ_CONFIG_FILE at ssh.kdl (Alt x, no rail)
        set -l config "\$HOME/.config/zellij/ssh.kdl"
        ssh $server zellij --config $config a $session
        or ssh $server zellij --config $config
    else if test -n "$(ssh $server command -v tmux)"
        set -l attach_argv
        set -l new_argv
        if test -n "$session"
            set attach_argv -t $session
            set new_argv -s $session
        end
        ssh $server tmux at $attach_argv
        or ssh $server tmux new $new_argv
    else
        ssh $server
    end
end
