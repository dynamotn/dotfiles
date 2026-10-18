function __caran_fzf_kube_namespace_change -d 'Switch the namespace of the current kubectl context'
    type -q kubectl; or return 1
    kubectl get namespaces -o name 2>/dev/null | string replace namespace/ '' | eval (__fzfcmd) "--prompt='namespace> '" | read -l namespace

    if test -n "$namespace"
        kubectl config set-context --current --namespace $namespace
    end

    commandline -f repaint
end
