# Usage: __caran_confirm PROMPT
function __caran_confirm -d 'Ask a yes/no question, default no' -a prompt
    read -l -P "$prompt [y/N] " answer; or return 1
    string match -qi -- 'y*' "$answer"
end
