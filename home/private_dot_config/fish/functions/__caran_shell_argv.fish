function __caran_shell_argv -d 'Print, one per line, the command that opens bash in a container or pod, else sh'
    # Not every image ships bash
    printf '%s\n' sh -c 'command -v bash >/dev/null && exec bash || exec sh'
end
