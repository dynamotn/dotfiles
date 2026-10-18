function ssht --description "Run terminal workspace after ssh"
    argparse -N1 s= -- $argv
    or return
    set -l server $argv
    set -l session $_flag_s

    if test -n "$(ssh $server command -v zellij)"
        ssh $server zellij a $session
        or ssh $server zellij --config "\$HOME/.config/zellij/ssh.kdl"
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
