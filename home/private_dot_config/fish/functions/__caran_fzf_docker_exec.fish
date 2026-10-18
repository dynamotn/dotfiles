function __caran_fzf_docker_exec -d 'Open a shell in a running container'
    type -q docker; or return 1
    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
        | eval (__fzfcmd) "--prompt='container> ' --delimiter='\t'" | read -l select

    if test -n "$select"
        set -l name (string split -f1 \t -- $select)
        # Not every image ships bash
        docker exec -it $name sh -c 'command -v bash >/dev/null && exec bash || exec sh'
    end

    commandline -f repaint
end
