function local_tunnel --description "Forward port from local to server"
    argparse -N1 'r=!_validate_int' 'l=!_validate_int' -- $argv
    or return
    if not set -q _flag_r; or not set -q _flag_l
        echo "Usage: local_tunnel -r <remote port> -l <local port> <host>" >&2
        return 1
    end
    ssh -R $_flag_r:localhost:$_flag_l -N -f $argv
end
