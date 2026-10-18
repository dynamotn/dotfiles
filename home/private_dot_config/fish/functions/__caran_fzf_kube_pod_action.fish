function __caran_fzf_kube_pod_action -d 'Pick a pod, then what to do with it'
    type -q kubectl; or return 1
    set -l pod (__caran_fzf_kube_pod_pick); or return 1

    printf '%s\n' logs exec describe delete | eval (__fzfcmd) "--prompt='$pod> '" | read -l action
    switch "$action"
        case logs
            kubectl logs -f --tail 50 $pod
        case exec
            # Not every image ships bash
            kubectl exec -it $pod -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'
        case describe
            kubectl describe pod $pod
        case delete
            read -l -P "Delete pod $pod? [y/N] " answer; or return 1
            string match -qi -- 'y*' "$answer"; and kubectl delete pod $pod
    end

    commandline -f repaint
end
