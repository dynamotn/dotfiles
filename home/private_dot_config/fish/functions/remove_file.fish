function remove_file --description "Remove files with some extra behaviors"
    set original_args $argv

    argparse r f -- $argv

    if not set -q _flag_r || set -q _flag_f
        command rm $original_args
        return
    end

    function confirm-remove --argument dir
        set display_dir (echo $dir | string replace $HOME '~')

        if confirm "Remove .git directory $display_dir?"
            command rm -rf $dir
            return
        end

        return 1
    end

    for f in $argv
        set gitdirs (find $f -mindepth 1 -name .git)
        for gitdir in $gitdirs
            if not confirm-remove $gitdir
                echo 'remove: cancelling.'
                return 1
            end
        end
    end

    # could be cool to allow remove .
    command rm $original_args
end
