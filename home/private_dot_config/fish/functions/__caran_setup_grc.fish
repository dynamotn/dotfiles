# Print a grc wrapper for each installed tool grc colours, for the startup to
# cache: testing some sixty names and defining the wrappers on every start
# cost more than reading them back. The names in $argv have an alternative of
# their own and get none.
function __caran_setup_grc
    set -l execs cat cvs df diff dig gcc g++ ifconfig make mount mtr netstat \
        ping ps tail traceroute wdiff blkid du dnf docker docker-compose \
        docker-machine env id ip iostat journalctl kubectl last lsattr lsblk \
        lspci lsmod lsof getfacl getsebool ulimit uptime nmap fdisk findmnt \
        free sar semanage sockstat ss sysctl systemctl stat showmount tcpdump \
        tune2fs vmstat w who

    if set -q grc_plugin_execs
        set execs $grc_plugin_execs
    end

    for executable in $execs
        if type -q $executable; and not contains -- $executable $argv
            printf 'function %s --wraps=%s\n    __caran_grc %s $argv\nend\n' \
                $executable $executable $executable
        end
    end
end
