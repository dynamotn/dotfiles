function __caran_fzf_kube_pod_pick -d 'Pick a pod of the current namespace, and print its name'
    type -q kubectl; or return 1
    kubectl get pods --no-headers 2>/dev/null \
        | __caran_fzf --prompt='pod> ' --preview='kubectl describe pod {1} 2>/dev/null | head -40' | read -l select
    test -n "$select"; or return 1
    string split -n -f1 ' ' -- $select
end
