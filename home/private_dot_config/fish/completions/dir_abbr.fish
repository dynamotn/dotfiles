complete -c dir_abbr -f
complete -c dir_abbr -n __fish_use_subcommand -a list -d 'Show the loaded abbreviations'
complete -c dir_abbr -n __fish_use_subcommand -a trust -d 'Review and trust the nearest .fish-abbr'
complete -c dir_abbr -n __fish_use_subcommand -a untrust -d 'Stop loading the nearest .fish-abbr'
complete -c dir_abbr -n '__fish_seen_subcommand_from trust' -a -y -d 'Trust without asking'
