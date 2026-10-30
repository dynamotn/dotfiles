# Usage: __caran_tunnel local_tunnel|remote_tunnel|sock_proxy ARGS...
function __caran_tunnel -d 'Parse the ports and open the ssh tunnel of local_tunnel, remote_tunnel or sock_proxy' -a name
    set -e argv[1]
    argparse -N1 'r=!_validate_int' 'l=!_validate_int' 'p=!_validate_int' -- $argv
    or return

    switch $name
        case local_tunnel
            if not set -q _flag_r; or not set -q _flag_l
                echo "Usage: local_tunnel -r <remote port> -l <local port> <host>" >&2
                return 1
            end
            ssh -R $_flag_r:localhost:$_flag_l -N -f $argv
        case remote_tunnel
            if not set -q _flag_r; or not set -q _flag_l
                echo "Usage: remote_tunnel -r <remote port> -l <local port> <host>" >&2
                return 1
            end
            ssh -L $_flag_l:localhost:$_flag_r -N -f $argv
        case sock_proxy
            if not set -q _flag_p
                echo "Usage: sock_proxy -p <local port> <host>" >&2
                return 1
            end
            ssh -f -C2qTnN -D $_flag_p $argv
    end
end
