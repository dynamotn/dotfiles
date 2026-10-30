function remove_file --description "Remove files with some extra behaviors"
    set -l original_args $argv
    argparse -i r/recursive R f/force -- $argv
    or return

    # A recursive removal that is not forced asks before taking a repository
    if set -q _flag_r; or set -q _flag_R; and not set -q _flag_f
        for f in (path filter -d -- $argv)
            for gitdir in (command find $f -mindepth 1 -name .git)
                if not __caran_confirm "Remove .git directory "(string replace $HOME '~' -- $gitdir)"?"
                    echo 'remove_file: cancelling.' >&2
                    return 1
                end
            end
        end
    end

    command rm $original_args
end
