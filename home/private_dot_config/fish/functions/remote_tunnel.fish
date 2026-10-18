function remote_tunnel --description "Forward port from server to local"
    argparse -N1 'r=!_validate_int' 'l=!_validate_int' -- $argv
    or return
    if not set -q _flag_r; or not set -q _flag_l
        echo "Usage: remote_tunnel -r <remote port> -l <local port> <host>" >&2
        return 1
    end
    ssh -L $_flag_l:localhost:$_flag_r -N -f $argv
end
