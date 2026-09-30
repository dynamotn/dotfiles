# What fish ships for helm is this one line, and a helm.fish here would shadow
# it, so keep it and fix what the generated completion gets wrong. It starts
# with `complete -c helm -e`, so nothing may be added before it.
helm completion fish 2>/dev/null | source

# Positional arguments already given to the current helm subcommand, so a rule
# can tell `helm upgrade <release>` from the chart path that follows it.
function __caran_helm_args --description 'Positional arguments of the current helm subcommand'
    set -l tokens (commandline -xpc)
    set -e tokens[1]
    for token in $tokens
        string match -q -- '-*' $token; and continue
        echo $token
    end
end

# A release name is asked from the cluster, and when helm cannot reach it the
# answer is the "default" directive, which fish reads as "offer file names".
# A file is never a release, so keep them out of the way.
complete -f -c helm -n '__fish_seen_subcommand_from get uninstall delete rollback status history test'
complete -f -c helm -n '__fish_seen_subcommand_from upgrade' \
    -n 'test (count (__caran_helm_args)) -eq 1'

# `helm dependency` works on the directory of a chart, not on any file
complete -f -c helm -n '__fish_seen_subcommand_from dependency' \
    -a '(__fish_complete_directories)'
