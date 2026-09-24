# Options and subcommands come straight from the dytoy option spec, so this
# cannot drift from the CLI the way a hand-written list did.
type -q dytoy; and dytoy completion --shell fish | source

# Tool names live in the YAML, which the option spec cannot describe.
type -q yq; and type -q dytoy; and yq e -r -o=j -I=0 '.[].name' \
    ~/.config/dytoy/tools.yaml 2>/dev/null | while read -l tool
    complete -xc dytoy -s t --arguments $tool
    complete -xc dytoy -l tool --arguments $tool
end
