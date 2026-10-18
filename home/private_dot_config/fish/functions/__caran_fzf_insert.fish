function __caran_fzf_insert -d 'Insert at the cursor the first line a picker prints' --argument-names picker
    set -l picked ($picker)
    if test -n "$picked[1]"
        commandline -i -- (string escape -- $picked[1])' '
    end
    commandline -f repaint
end
