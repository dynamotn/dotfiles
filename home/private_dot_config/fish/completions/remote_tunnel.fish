complete -xc remote_tunnel -d Hostname --arguments "(__fish_print_hostnames)"
__caran_print_common_port | while read -l description port
    complete -xc remote_tunnel -s r -d $description --arguments $port --condition __caran_need_ssh_argument

end
complete -fc remote_tunnel -s l -d "Local port"
complete -fc remote_tunnel -s r -d "Remote port"
