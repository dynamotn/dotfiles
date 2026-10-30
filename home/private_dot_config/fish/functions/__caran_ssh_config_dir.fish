# Automatically merge ssh configs from subfolder
function __caran_ssh_config_dir
    set -l ssh_config $HOME/.ssh/config
    set -l ssh_config_dir $HOME/.ssh/config.d

    if not test -d $ssh_config_dir
        command mkdir $ssh_config_dir
        command mv $ssh_config $ssh_config_dir/base.config
        echo "Your OpenSSH config was moved to new directory $ssh_config_dir" >&2
    end

    set -l parts $ssh_config_dir/**.config
    # Keep the current config when there is nothing to merge
    test (count $parts) -gt 0; or return 0

    # Build aside and move into place, so a failure or a parallel ssh never leaves it empty
    set -l tmp (command mktemp $ssh_config.XXXXXX); or return 1
    if command cat $parts >$tmp
        command chmod 600 $tmp
        command mv -f $tmp $ssh_config
    else
        command rm -f $tmp
        return 1
    end
end
