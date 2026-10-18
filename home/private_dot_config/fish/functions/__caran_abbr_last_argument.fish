function __caran_abbr_last_argument --description 'Expand `!$` to the last argument of the previous command'
    # Split the way the shell would, so a quoted argument stays whole
    echo -- $history[1] | read -lat tokens
    if test (count $tokens) -gt 1
        string escape -- $tokens[-1]
    else
        echo -- '!$'
    end
end
