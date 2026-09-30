# What fish ships for kubectl is this one line, and a kubectl.fish here would
# shadow it, so keep it and fix what the generated completion gets wrong.
kubectl completion fish 2>/dev/null | source

# `kubectl config` answers most of its subcommands with the "default" directive,
# which fish reads as "offer file names" - none of them takes a path.
complete -f -c kubectl -n '__fish_seen_subcommand_from config' \
    -n '__fish_seen_subcommand_from current-context get-contexts get-clusters get-users view unset set set-cluster set-credentials set-context'

# The two that name a cluster or a user get them from the kubeconfig, the way
# kubectl already does it for contexts
complete -f -c kubectl -n '__fish_seen_subcommand_from config' -n '__fish_seen_subcommand_from set-cluster' \
    -a '(kubectl config view -o jsonpath="{.clusters[*].name}" 2>/dev/null | string split " ")' -d Cluster
complete -f -c kubectl -n '__fish_seen_subcommand_from config' -n '__fish_seen_subcommand_from set-credentials' \
    -a '(kubectl config view -o jsonpath="{.users[*].name}" 2>/dev/null | string split " ")' -d User

# `-k` points at the directory holding a kustomization.yaml, never at a file
complete -x -c kubectl -s k -l kustomize -a '(__fish_complete_directories)' -d 'Kustomization directory'
