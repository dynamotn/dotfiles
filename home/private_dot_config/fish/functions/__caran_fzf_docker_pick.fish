function __caran_fzf_docker_pick -d 'Pick a running container, and print its name'
    type -q docker; or return 1
    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
        | __caran_fzf --prompt='container> ' --delimiter='\t' | read -l select
    test -n "$select"; or return 1
    string split -f1 \t -- $select
end
