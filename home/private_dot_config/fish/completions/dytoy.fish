complete -xc dytoy -s l -d "Set log level"
complete -xc dytoy -l log-level -d "Set log level"
for log_level in trace debug info warn error fatal
    complete -xc dytoy -s l --arguments $log_level
    complete -xc dytoy -l log-level --arguments $log_level
end
complete -xc dytoy -s D -d "Dry run"
complete -xc dytoy -l dry-run -d "Dry run"
complete -xc dytoy -s t -d "Only one specific tool"
complete -xc dytoy -l tool -d "Only one specific tool"
complete -xc dytoy -s e -d "Install only essential tool"
complete -xc dytoy -l essential -d "Install only essential tool"
complete -xc dytoy -s i -d "Install only not installed tool"
complete -xc dytoy -l check-installed -d "Install only not installed tool"
complete -xc dytoy -l no-check-installed -d "Allow to reinstall tool"
type -q yq; and yq e -r -o=j -I=0 '.[].name' \
    ~/.config/dytoy/tools.yaml | while read -l tool
    complete -xc dytoy -s t --arguments $tool
end
complete -xc dytoy -s L -d "List files in compressed instead of extract"
complete -xc dytoy -l list -d "List files in compressed instead of extract"
complete -xc dytoy -s h -d "Display help"
complete -xc dytoy -l help -d "Display help"
