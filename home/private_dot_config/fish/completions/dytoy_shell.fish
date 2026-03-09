complete -xc dytoy_shell -s l -d "Set log level"
complete -xc dytoy_shell -l log-level -d "Set log level"
for log_level in trace debug info warn error fatal
    complete -xc dytoy_shell -s l --arguments $log_level
    complete -xc dytoy_shell -l log-level --arguments $log_level
end
complete -xc dytoy_shell -s D -d "Dry run"
complete -xc dytoy_shell -l dry-run -d "Dry run"
complete -xc dytoy_shell -s t -d "Only one specific tool"
complete -xc dytoy_shell -l tool -d "Only one specific tool"
complete -xc dytoy_shell -s e -d "Install only essential tool"
complete -xc dytoy_shell -l essential -d "Install only essential tool"
complete -xc dytoy_shell -s i -d "Install only not installed tool"
complete -xc dytoy_shell -l check-installed -d "Install only not installed tool"
complete -xc dytoy_shell -l no-check-installed -d "Allow to reinstall tool"
type -q yq; and yq e -r -o=j -I=0 'filter(.method == "shell") | .[].name' \
    ~/.config/dytoy/tools.yaml | while read -l tool
    complete -xc dytoy_shell -s t --arguments $tool
end
complete -xc dytoy_shell -s h -d "Display help"
complete -xc dytoy_shell -l help -d "Display help"
