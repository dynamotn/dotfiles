alias cz chezmoi
alias cza 'cz apply'
alias czA 'cz add'
alias czAe 'cz add --encrypt'
alias cze 'cz edit'
# Scripts stay out of the diff: rendering them can read secrets, which the
# diff would print in clear.
alias czd 'cz diff --recursive --exclude scripts'
alias czu 'cz update'
alias czs 'cz status'

alias czDd 'cz dycrypt decrypt'
alias czDe 'cz dycrypt encrypt'

alias scza 'scz apply'
alias sczA 'scz add'
alias sczAe 'scz add --encrypt'
alias scze 'scz edit'
# Scripts stay out of the system diff: rendering them reads secrets (the Wi-Fi
# script asks rbw for passwords) and the diff would print those in clear.
alias sczd 'scz diff --recursive --exclude scripts'
alias sczu 'scz update'
alias sczs 'scz status'
