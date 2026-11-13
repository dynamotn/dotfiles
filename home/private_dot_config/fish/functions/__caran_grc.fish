# Run a tool through grc at a terminal, and as it is anywhere else
function __caran_grc --argument-names executable
    if isatty 1
        set -l optionsvariable "grcplugin_"$executable
        set -l options $$optionsvariable
        grc -es --colour=auto $executable $options $argv[2..-1]
    else
        # No `eval` here: it re-parses the arguments, and an empty one then
        # disappears. Completion scripts pass exactly that to ask for
        # "complete the next, still empty word".
        command $executable $argv[2..-1]
    end
end
