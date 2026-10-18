function __caran_notify_text --description 'Print the title and body announcing the end of a command' --argument-names exit_status duration_ms cmdline
    test $exit_status -eq 0; and echo Done; or echo "Failed ($exit_status)"

    set -l shown (string shorten -m 80 -- (string replace -a \n ' ' -- $cmdline))
    # A command carrying a credential is shown by its program name only
    __caran_history_has_secret "$cmdline"; and set shown (string split -f1 ' ' -- (string trim -- $cmdline))
    echo "$shown · "(math -s0 $duration_ms / 1000)s
end
