function __caran_fzf_kube_pod_action -d 'Pick a pod, then what to do with it'
    type -q kubectl; or return 1
    set -l pod (__caran_fzf_kube_pod_pick); or return 1

    printf '%s\n' logs exec describe delete | __caran_fzf --prompt="$pod> " | read -l action
    switch "$action"
        case logs
            kubectl logs -f --tail 50 $pod
        case exec
            kubectl exec -it $pod -- (__caran_shell_argv)
        case describe
            kubectl describe pod $pod
        case delete
            __caran_confirm "Delete pod $pod?"; and kubectl delete pod $pod
    end

    commandline -f repaint
end
