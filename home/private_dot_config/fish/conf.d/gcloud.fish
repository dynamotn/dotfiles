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

set -q FZF_GCLOUD_PROJECT_SWITCH_COMMAND; or set -g FZF_GCLOUD_PROJECT_SWITCH_COMMAND "gcloud config set project \$project_id"
set -q FZF_GCLOUD_PROJECT_SEARCH_COMMAND; or set -g FZF_GCLOUD_PROJECT_SEARCH_COMMAND "gcloud projects list --format='table[no-heading](projectId,name)'"
set -q FZF_GCLOUD_INSTANCE_SEARCH_COMMAND; or set -g FZF_GCLOUD_INSTANCE_SEARCH_COMMAND "gcloud compute instances list | tail -n +2"
set -q FZF_GCLOUD_ACTIVE_INSTANCE_SEARCH_COMMAND; or set -g FZF_GCLOUD_ACTIVE_INSTANCE_SEARCH_COMMAND "gcloud compute instances list --filter=\"status=RUNNING\" | tail -n +2"
