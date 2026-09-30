# What fish ships for chezmoi is this one line, and a chezmoi.fish here would
# shadow it, so keep it and teach it `dycrypt`: chezmoi dispatches an unknown
# subcommand to `chezmoi-<name>` the way git does, and knows nothing about the
# options of that one.
chezmoi completion fish 2>/dev/null | source

complete -f -c chezmoi -n 'not __fish_seen_subcommand_from dycrypt' \
    -a dycrypt -d 'Decrypt and encrypt secrets data'
__caran_dycrypt_complete chezmoi
