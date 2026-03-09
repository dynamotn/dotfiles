complete -xc dytoy_os -s l -d "Set log level"
complete -xc dytoy_os -l log-level -d "Set log level"
for log_level in trace debug info warn error fatal
    complete -xc dytoy_os -s l --arguments $log_level
    complete -xc dytoy_os -l log-level --arguments $log_level
end
complete -xc dytoy_os -s D -d "Dry run"
complete -xc dytoy_os -l dry-run -d "Dry run"
complete -xc dytoy_os -s t -d "Only one specific tool"
complete -xc dytoy_os -l tool -d "Only one specific tool"
complete -xc dytoy_os -s e -d "Install only essential tool"
complete -xc dytoy_os -l essential -d "Install only essential tool"
complete -xc dytoy_os -s i -d "Install only not installed tool"
complete -xc dytoy_os -l check-installed -d "Install only not installed tool"
complete -xc dytoy_os -l no-check-installed -d "Allow to reinstall tool"
type -q yq; and yq e -r -o=j -I=0 'filter(.method == "os") | .[].name' \
    ~/.config/dytoy/tools.yaml | while read -l tool
    complete -xc dytoy_os -s t --arguments $tool
end
complete -xc dytoy_binary -l sync -d "Sync package repositories before install"
complete -xc dytoy_binary -l no-sync -d "Sync package repositories before install"
complete -xc dytoy_os -s h -d "Display help"
complete -xc dytoy_os -l help -d "Display help"
