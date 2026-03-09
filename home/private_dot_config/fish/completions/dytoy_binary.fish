complete -xc dytoy_binary -s l -d "Set log level"
complete -xc dytoy_binary -l log-level -d "Set log level"
for log_level in trace debug info warn error fatal
    complete -xc dytoy_binary -s l --arguments $log_level
    complete -xc dytoy_binary -l log-level --arguments $log_level
end
complete -xc dytoy_binary -s D -d "Dry run"
complete -xc dytoy_binary -l dry-run -d "Dry run"
complete -xc dytoy_binary -s t -d "Only one specific tool"
complete -xc dytoy_binary -l tool -d "Only one specific tool"
complete -xc dytoy_binary -s e -d "Install only essential tool"
complete -xc dytoy_binary -l essential -d "Install only essential tool"
complete -xc dytoy_binary -s i -d "Install only not installed tool"
complete -xc dytoy_binary -l check-installed -d "Install only not installed tool"
complete -xc dytoy_binary -l no-check-installed -d "Allow to reinstall tool"
type -q yq; and yq e -r -o=j -I=0 'filter(.method == "binary") | .[].name' \
    ~/.config/dytoy/tools.yaml | while read -l tool
    complete -xc dytoy_binary -s t --arguments $tool
end
complete -xc dytoy_binary -s L -d "List files in compressed instead of extract"
complete -xc dytoy_binary -l list -d "List files in compressed instead of extract"
complete -xc dytoy_binary -s h -d "Display help"
complete -xc dytoy_binary -l help -d "Display help"
