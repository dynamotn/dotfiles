function ssht --description "Run terminal workspace after ssh"
    getopts $argv | while read -l key value
        switch "$key"
            case _
                if test -z "$server"
                    set server $value
                else
                    set server $server $value
                end
            case s
                set session $value
        end
    end
    if not test -n "$server"
        echo "Must have hostname"
        return 1
    end

    if ! test -z "$(ssh $server command -v zellij)"
        ssh $server zellij a $session
        or ssh $server zellij
    else if ! test -z "$(ssh $server command -v tmux)"
        if test -n "$session"
            set attach_argv "-t $session"
            set new_argv "-s $session"
        end
        ssh $server tmux at $attach_argv
        or ssh $server tmux new $new_argv
    else
        ssh $server
    end
end
