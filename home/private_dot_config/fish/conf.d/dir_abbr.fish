status is-interactive; or exit

# Abbreviations of a project, from the nearest `.fish-abbr` above $PWD: one
# `name expansion…` per line, `#` for comments. Enter expands and runs at
# once, so a file is loaded only once `dir_abbr trust` has recorded its hash;
# editing it changes the hash and asks for trust again.
function __caran_dir_abbr_load --on-variable PWD --description 'Load the abbreviations of the nearest .fish-abbr'
    set -l file (__caran_dir_abbr_find)
    test "$file" = "$__caran_dir_abbr_file"; and return

    __caran_dir_abbr_unload
    test -n "$file"; or return
    if not __caran_dir_abbr_is_trusted $file
        set_color brblack
        echo "dir_abbr: $file is not trusted; review it, then run `dir_abbr trust`" >&2
        set_color normal
        return
    end

    set -g __caran_dir_abbr_file $file
    set -g __caran_dir_abbr_names
    for line in (string trim <$file | string match -rv '^(#|$)')
        set -l parts (string split -m1 ' ' -- $line)
        set -l name $parts[1]
        # A name of its own only: never take over an abbreviation defined elsewhere
        string match -qr '^[A-Za-z0-9_.-]+$' -- $name; or continue
        abbr --query -- $name; and continue
        test -n "$parts[2]"; or continue
        abbr -a -- $name (string trim -- $parts[2])
        set -a __caran_dir_abbr_names $name
    end
end

function __caran_dir_abbr_unload --description 'Erase the abbreviations loaded from a .fish-abbr'
    for name in $__caran_dir_abbr_names
        abbr --erase -- $name
    end
    set -e __caran_dir_abbr_names
    set -e __caran_dir_abbr_file
end

function __caran_dir_abbr_find --description 'Print the nearest .fish-abbr above $PWD'
    set -l dir $PWD
    while true
        if test -f $dir/.fish-abbr
            echo $dir/.fish-abbr
            return 0
        end
        test "$dir" = /; and return 1
        set dir (path dirname -- $dir)
    end
end

function __caran_dir_abbr_hash --argument-names file
    if type -q sha256sum
        sha256sum -- $file | string split -f1 ' '
    else
        shasum -a 256 -- $file | string split -f1 ' '
    end
end

function __caran_dir_abbr_trust_file
    echo $__fish_user_data_dir/dir_abbr_trust
end

function __caran_dir_abbr_is_trusted --argument-names file
    set -l store (__caran_dir_abbr_trust_file)
    test -f $store; or return 1
    contains -- (__caran_dir_abbr_hash $file)"  $file" (command cat $store)
end

__caran_dir_abbr_load
