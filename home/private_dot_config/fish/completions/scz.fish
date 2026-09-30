# scz is the sudo wrapper that applies the `root/` source to `/`, and it hands
# its arguments straight to chezmoi, so it takes chezmoi's own completion.
complete -c scz -w chezmoi
