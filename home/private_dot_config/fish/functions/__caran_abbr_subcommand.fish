function __caran_abbr_subcommand --description 'Expand a short subcommand, only right after its command' --argument-names token
    # `--command git` alone would expand the word anywhere after `git`, a file
    # or branch named `co` included: only the first argument is a subcommand.
    set -l words (commandline -xpc)
    if test (count $words) -eq 1
        for entry in $__caran_subcommand_abbrs
            set -l parts (string split -m2 : -- $entry)
            if test "$parts[1]" = (path basename -- $words[1]); and test "$parts[2]" = "$token"
                echo -- $parts[3]
                return 0
            end
        end
    end
    echo -- $token
end
