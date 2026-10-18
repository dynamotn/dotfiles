function sock_proxy --description "Create SOCK5 proxy via server on local"
    argparse -N1 'p=!_validate_int' -- $argv
    or return
    if not set -q _flag_p
        echo "Usage: sock_proxy -p <local port> <host>" >&2
        return 1
    end
    ssh -f -C2qTnN -D $_flag_p $argv
end
