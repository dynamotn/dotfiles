function __caran_fzf_kube_context_change -d 'Switch the kubectl context'
    type -q kubectl; or return 1
    set -l current (kubectl config current-context 2>/dev/null)
    kubectl config get-contexts -o name 2>/dev/null | __caran_fzf --prompt='context> ' --header="current: $current" | read -l context

    if test -n "$context"
        kubectl config use-context $context
    end

    commandline -f repaint
end
