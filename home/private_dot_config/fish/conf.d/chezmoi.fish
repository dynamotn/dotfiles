abbr -a cz chezmoi
abbr -a cza 'chezmoi apply'
abbr -a czA 'chezmoi add'
abbr -a czAe 'chezmoi add --encrypt'
abbr -a cze 'chezmoi edit'
# Scripts stay out of the diff: rendering them can read secrets, which the
# diff would print in clear.
abbr -a czd 'chezmoi diff --recursive --exclude scripts'
abbr -a czu 'chezmoi update'
abbr -a czs 'chezmoi status'

abbr -a czDd 'chezmoi dycrypt decrypt'
abbr -a czDe 'chezmoi dycrypt encrypt'

abbr -a scza 'scz apply'
abbr -a sczA 'scz add'
abbr -a sczAe 'scz add --encrypt'
abbr -a scze 'scz edit'
# Scripts stay out of the system diff: rendering them reads secrets (the Wi-Fi
# script asks rbw for passwords) and the diff would print those in clear.
abbr -a sczd 'scz diff --recursive --exclude scripts'
abbr -a sczu 'scz update'
abbr -a sczs 'scz status'

alias fcz __caran_fzf_chezmoi_edit

# The fzf picker takes no argument
complete -c fcz -f
