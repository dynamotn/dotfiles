function fish_should_add_to_history --description 'Keep commands carrying a credential out of the history' --argument-names cmdline
    # Defining this function replaces the built-in rule, so keep it: a
    # command typed with a leading space stays out of the history.
    string match -q -- ' *' "$cmdline"; and return 1

    __caran_history_has_secret "$cmdline"; or return 0
    # Say so, or the command is only missed the next time it is searched for
    if test "$history_secret_notice" != 0; and status is-interactive
        set_color brblack
        echo '(carries a credential: not saved to history)' >&2
        set_color normal
    end
    return 1
end
