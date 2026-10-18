function __caran_fzf_docker_exec -d 'Open a shell in a running container'
    set -l name (__caran_fzf_docker_pick); or return 1
    # Not every image ships bash
    docker exec -it $name sh -c 'command -v bash >/dev/null && exec bash || exec sh'

    commandline -f repaint
end
