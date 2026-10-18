abbr -a d docker
abbr -a db 'docker build'
abbr -a di 'docker image'
abbr -a dl 'docker logs -f --tail 50'
abbr -a dph 'docker push'
abbr -a dpl 'docker pull'
abbr -a dps 'docker ps'
abbr -a dr 'docker run'
abbr -a drm 'docker rm'
abbr -a drmi 'docker rmi'
abbr -a drs 'docker restart'
abbr -a dsp 'docker system prune'
abbr -a dw 'docker inspect'
abbr -a dx 'docker exec -it'

# dytoy installs the standalone Compose v2 binary under this name
abbr -a c docker-compose
abbr -a cb 'docker-compose build'
abbr -a cl 'docker-compose logs -f --tail 50'
abbr -a cpl 'docker-compose pull'
abbr -a crs 'docker-compose restart'
abbr -a cu 'docker-compose up'
abbr -a cx 'docker-compose exec'

alias fdx __caran_fzf_docker_exec

# The fzf picker takes no argument
complete -c fdx -f
