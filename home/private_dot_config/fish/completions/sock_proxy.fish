complete -xc sock_proxy -d Hostname --arguments "(__fish_print_hostnames)"
__caran_print_common_port | while read -l description port
    complete -xc sock_proxy -s p -d $description --arguments $port --condition __caran_need_ssh_argument
end
complete -fc sock_proxy -s p -d Port
