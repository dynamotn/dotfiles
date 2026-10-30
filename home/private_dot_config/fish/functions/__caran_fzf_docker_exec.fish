function __caran_fzf_docker_exec -d 'Open a shell in a running container'
    set -l name (__caran_fzf_docker_pick); or return 1
    docker exec -it $name (__caran_shell_argv)

    commandline -f repaint
end
