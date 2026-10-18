function dir_abbr --description 'Trust, untrust or list the abbreviations of the nearest .fish-abbr'
    set -l file (__caran_dir_abbr_find)
    set -l store (__caran_dir_abbr_trust_file)

    switch "$argv[1]"
        case trust
            test -n "$file"; or begin
                echo 'dir_abbr: no .fish-abbr above this directory' >&2
                return 1
            end
            # Shown in full: what is trusted is what Enter will run
            echo "$file:"
            cat -- $file
            if not contains -- -y $argv[2..]
                read -l -P 'Trust these abbreviations? [y/N] ' answer; or return 1
                string match -qi -- 'y*' "$answer"; or return 1
            end
            mkdir -p (path dirname -- $store)
            # One line per file: a new hash replaces the one of its old content
            set -l kept
            test -f $store; and set kept (string match -v -- "*  $file" <$store)
            printf '%s\n' $kept (__caran_dir_abbr_hash $file)"  $file" >$store
            set -e __caran_dir_abbr_file
            __caran_dir_abbr_load
        case untrust
            test -n "$file"; and test -f $store; or return 0
            set -l kept (string match -v -- "*  $file" <$store)
            printf '%s\n' $kept >$store
            __caran_dir_abbr_unload
        case list ''
            if test -n "$__caran_dir_abbr_file"
                echo "$__caran_dir_abbr_file:"
                for name in $__caran_dir_abbr_names
                    abbr --show | string match -e -- " $name "
                end
            else if test -n "$file"
                echo "$file is not trusted"
            else
                echo 'No .fish-abbr above this directory'
            end
        case '*'
            echo 'Usage: dir_abbr [list | trust [-y] | untrust]' >&2
            return 2
    end
end
