function __caran_history_has_secret --description 'Whether a command line carries a credential' --argument-names cmdline
    for pattern in (__caran_history_secret_patterns)
        string match -qr -- $pattern "$cmdline"; and return 0
    end
    return 1
end
