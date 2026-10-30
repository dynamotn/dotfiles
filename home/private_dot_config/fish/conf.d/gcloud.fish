abbr -a G gcloud
abbr -a Gal "gcloud auth login"
abbr -a Gb "bq query --use_legacy_sql=false"
abbr -a Gc "gcloud compute"
abbr -a Gca "gcloud compute addresses"
abbr -a Gci "gcloud compute instances"
abbr -a Gcf "gcloud compute firewall-rules"
abbr -a Gi "gcloud iam"
abbr -a Gk "gcloud container"
abbr -a Gl "gcloud logging"
abbr -a Gp "gcloud pubsub"
abbr -a Gs "gcloud sql"
abbr -a Gu "gcloud components update"

alias fGpc __caran_fzf_gcloud_project_change
alias fGcis __caran_fzf_gcloud_instance_ssh
alias fGciS __caran_fzf_gcloud_instance_search

# The fzf pickers take no argument
complete -c fGpc -f
complete -c fGcis -f
complete -c fGciS -f
