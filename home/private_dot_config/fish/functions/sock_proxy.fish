function sock_proxy --description "Create SOCK5 proxy via server on local"
    getopts $argv | while read -l key value
        switch "$key"
            case _
                if test -z "$server"
                    set server $value
                else
                    set server $server $value
                end
            case p
                set port $value
        end
    end
    if not test -n "$server"
        echo "Must have hostname"
        return 1
    end
    if not test -n "$port"
        echo "Must have port"
        return 1
    end
    ssh -f -C2qTnN -D $port $server
end
