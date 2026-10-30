# Usage: __caran_tunnel_complete COMMAND COMMON_PORT_FLAG FLAG DESCRIPTION...
function __caran_tunnel_complete -d 'Complete a command of __caran_tunnel' -a name common_flag
    complete -xc $name -d Hostname --arguments "(__fish_print_hostnames)"
    __caran_print_common_port | while read -l description port
        complete -xc $name -s $common_flag -d $description --arguments $port --condition __caran_need_ssh_argument
    end
    for i in (seq 3 2 (count $argv))
        complete -fc $name -s $argv[$i] -d $argv[(math $i + 1)]
    end
end
