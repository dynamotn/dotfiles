# History shortcuts, anywhere on the line: `sudo !!`, `cd !$`
abbr -a __caran_last_command --position anywhere --regex '^!!$' --function __caran_abbr_last_command
abbr -a __caran_last_argument --position anywhere --regex '^!\$$' --function __caran_abbr_last_argument
# `...` is `../..`, `..../src` is `../../../src`
abbr -a __caran_up_dirs --position anywhere --regex '^\.{3,}(/.*)?$' --function __caran_abbr_up_dirs

# Short subcommands, expanded only as the first argument of their command
set -g __caran_subcommand_abbrs \
    git:br:branch git:ci:commit git:co:checkout git:st:status git:sw:switch \
    kubectl:a:'apply -f' kubectl:d:describe kubectl:e:edit kubectl:g:get kubectl:l:logs kubectl:x:'exec -it' \
    docker:i:image docker:l:'logs -f --tail 50' docker:x:'exec -it'
for command in (string split -f1 : -- $__caran_subcommand_abbrs | sort -u)
    set -l names (string replace -rf -- "^$command:([^:]+):.*" '$1' $__caran_subcommand_abbrs)
    abbr -a __caran_sub_$command --command $command --regex '^('(string join '|' -- $names)')$' --function __caran_abbr_subcommand
end
