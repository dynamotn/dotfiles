function history_scrub --description 'Delete the history entries that carry a credential'
    argparse h/help n/dry-run y/yes -- $argv; or return 2
    if set -q _flag_help
        echo 'Usage: history_scrub [-n | --dry-run] [-y | --yes]'
        echo
        echo 'List the history entries fish_should_add_to_history would have refused,'
        echo 'with the credential masked, then delete them once confirmed.'
        echo '  -n, --dry-run  only list them'
        echo '  -y, --yes      delete without asking'
        return 0
    end

    set -l patterns (__caran_history_secret_patterns)
    # One builtin call per entry: a function call each would take seconds on a
    # long history. An entry can span several lines, hence the NUL split.
    set -l any '(?:'(string join ')|(?:' -- $patterns)')'
    set -l found
    for entry in (history --null | string split0)
        string match -qr -- $any $entry; and set -a found $entry
    end

    if test (count $found) -eq 0
        echo 'No history entry carries a credential.'
        return 0
    end

    # Never print the credential itself, not even to the terminal it came from
    for entry in $found
        set -l masked $entry
        for pattern in $patterns
            set masked (string replace -ra -- $pattern '[REDACTED]' $masked)
        end
        printf '  %s\n' (string shorten -m 100 -- (string join ' ' -- $masked))
    end
    printf '%d history entries carry a credential.\n' (count $found)

    set -q _flag_dry_run; and return 0
    if not set -q _flag_yes
        read -l -P 'Delete them? [y/N] ' answer; or return 1
        string match -qi -- 'y*' "$answer"; or return 1
    end
    history delete --exact --case-sensitive -- $found
    history save
    printf 'Deleted %d entries.\n' (count $found)
end
