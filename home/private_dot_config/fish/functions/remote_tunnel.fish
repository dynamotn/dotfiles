function remote_tunnel --description "Forward port from server to local"
    getopts $argv | while read -l key value
        switch "$key"
            case _
                if test -z "$server"
                    set server $value
                else
                    set server $server $value
                end
            case r
                set remote_port $value
            case l
                set local_port $value
        end
    end
    if not test -n "$server"
        echo "Must have hostname"
        return 1
    end
    if not test -n "$remote_port"
        echo "Must have remote port"
        return 1
    end
    if not test -n "$local_port"
        echo "Must have local port"
        return 1
    end
    ssh -L $local_port:localhost:$remote_port -N -f $server
end
