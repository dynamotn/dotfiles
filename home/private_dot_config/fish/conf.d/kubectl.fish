abbr -a k kubectl
abbr -a ka 'kubectl apply -f'
abbr -a kc 'kubectl create'
abbr -a kccc 'kubectl config current-context'
abbr -a kcdc 'kubectl config delete-context'
abbr -a kcsc 'kubectl config set-context'
abbr -a kcuc 'kubectl config use-context'
abbr -a kd 'kubectl describe'
abbr -a kdel 'kubectl delete'
abbr -a ke 'kubectl edit'
abbr -a kg 'kubectl get'
abbr -a kgj 'kubectl get -o json'
abbr -a kgy 'kubectl get -o yaml'
abbr -a kk 'kubectl apply -k'
abbr -a kl 'kubectl logs'
abbr -a klf 'kubectl logs -f --tail 50'
abbr -a ksc 'kubectl scale'
abbr -a kr 'kubectl rollout'
abbr -a kx 'kubectl exec -it'

alias fkctx __caran_fzf_kube_context_change
alias fkns __caran_fzf_kube_namespace_change

# The fzf pickers take no argument
complete -c fkctx -f
complete -c fkns -f

abbr -a h helm
abbr -a hd helm-docs
abbr -a hdel 'helm delete'
abbr -a hdu 'helm dependency update'
abbr -a hgv 'helm get values'
abbr -a hl 'helm ls'
abbr -a hs 'helm secrets'
abbr -a hu 'helm upgrade --install'
