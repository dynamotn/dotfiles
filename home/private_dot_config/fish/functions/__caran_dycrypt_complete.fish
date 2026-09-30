# The options come from the spec in `home/dot_local/bin/executable_chezmoi-dycrypt.tmpl`;
# the values they accept come from the validators that spec names, in
# `scripts/lib/dycrypt.sh`, `scripts/lib/chezmoi_attrs.sh` and dybatpho.

function __caran_dycrypt_args --description 'Positional arguments of a chezmoi-dycrypt line'
    set -l tokens (commandline -xpc)
    set -e tokens[1]
    # `chezmoi dycrypt ...` reaches the same CLI as `chezmoi-dycrypt ...`
    test "$tokens[1]" = dycrypt; and set -e tokens[1]
    set -l skip 0
    for token in $tokens
        if test $skip -eq 1
            set skip 0
            continue
        end
        # These carry their value in the next token, which is not an argument
        if string match -qr -- '^(-l|--log-level|-i|--identity-type|-f|--folder|-a|--attributes)$' $token
            set skip 1
            continue
        end
        string match -q -- '-*' $token; and continue
        echo $token
    end
end

function __caran_dycrypt_identities --description 'Identity types that have an age key here'
    set -l config $HOME/.config/chezmoi/chezmoi.yaml
    type -q yq; and test -r $config; or return
    string match -q true -- (yq e '.data.decryptPersonal' $config 2>/dev/null); and echo personal
    set -l companies (yq e '.data.decryptEnterprise[]' $config 2>/dev/null)
    set -q companies[1]; or return
    echo enterprise-shared
    printf 'enterprise-%s\n' $companies
end

function __caran_dycrypt_option --argument-names short long \
    --description 'Value an option was given on the current dycrypt line'
    set -l tokens (commandline -xpc)
    set -l want 0
    for token in $tokens
        if test $want -eq 1
            echo $token
            return
        end
        switch $token
            case $short $long
                set want 1
            case "$long=*"
                string replace -- "$long=" '' $token
                return
        end
    end
end

function __caran_dycrypt_dotfiles --description 'Root of the dotfiles repository'
    set -l config $HOME/.config/chezmoi/chezmoi.yaml
    type -q yq; and test -r $config; or return 1
    set -l root (yq e '.sourceDir' $config 2>/dev/null)
    test -n "$root"; and test "$root" != null; or return 1
    echo $root
end

function __caran_dycrypt_files --description 'Names the store already holds'
    set -l identity (__caran_dycrypt_option -i --identity-type)
    test -n "$identity"; or set identity personal
    set -l folder (__caran_dycrypt_option -f --folder)
    test -n "$folder"; or set folder data

    set -l dir
    if test "$folder" = data
        set dir (__caran_dycrypt_dotfiles)/secrets/data/$identity
    else
        set dir (path normalize (string replace -r '^~' $HOME -- $folder))
    end
    test -d "$dir"; or return

    # Both commands name the file by its plain name: `decrypt` writes it,
    # `encrypt` reads it. So one lists the ciphertext, the other the plaintext.
    if contains -- decrypt (__caran_dycrypt_args)
        set -l ciphers $dir/**.age
        for file in $ciphers
            string replace -- "$dir/" '' $file | string replace -r '\.age$' ''
        end
    else
        set -l plains $dir/**
        for file in $plains
            test -f "$file"; or continue
            string match -q -- '*.age' $file; and continue
            string replace -- "$dir/" '' $file
        end
    end
end

function __caran_dycrypt_attributes --description 'chezmoi attributes, as a comma separated list'
    set -l given (string split -- , (commandline -ct))
    set -l prefix ""
    test (count $given) -gt 1; and set prefix (string join , $given[1..-2]),
    for attr in create encrypted private readonly empty executable
        contains -- $attr $given; and continue
        echo $prefix$attr
    end
end

function __caran_dycrypt_complete --argument-names cmd \
    --description 'Add the completions of chezmoi-dycrypt to a command name'
    # Under `chezmoi` the whole CLI hangs off the `dycrypt` word; called by its
    # own name, it is the command itself.
    set -l when true
    test "$cmd" = chezmoi-dycrypt; or set when '__fish_seen_subcommand_from dycrypt'

    complete -f -c $cmd -n "$when" -n 'test (count (__caran_dycrypt_args)) -eq 0' \
        -a decrypt -d 'Decrypt secrets data'
    complete -f -c $cmd -n "$when" -n 'test (count (__caran_dycrypt_args)) -eq 0' \
        -a encrypt -d 'Encrypt secrets data and target file'
    # The names come from the store the command would read: the `.age` files of
    # `secrets/data/<identity>` for `decrypt`, the plain ones for `encrypt`, or
    # the contents of `--folder` when it is not the data store. Only names are
    # listed, never what is inside them. `decrypt` takes a single file,
    # `encrypt` takes as many as you name.
    complete -f -c $cmd -n "$when" -n '__fish_seen_subcommand_from decrypt' \
        -n 'test (count (__caran_dycrypt_args)) -eq 1' \
        -a '(__caran_dycrypt_files)' -d Secret
    complete -f -c $cmd -n "$when" -n '__fish_seen_subcommand_from encrypt' \
        -a '(__caran_dycrypt_files)' -d Secret
    # Past that single file, `decrypt` takes nothing more
    complete -f -c $cmd -n "$when" -n '__fish_seen_subcommand_from decrypt' \
        -n 'test (count (__caran_dycrypt_args)) -ge 2'

    complete -x -c $cmd -n "$when" -s l -l log-level \
        -a 'trace debug info warn error fatal' -d 'Log level'
    complete -f -c $cmd -n "$when" -s D -l dry-run -d 'Dry run'
    complete -x -c $cmd -n "$when" -s i -l identity-type \
        -a '(__caran_dycrypt_identities)' -d 'Identity type'
    complete -x -c $cmd -n "$when" -s f -l folder -a data \
        -d 'Folder of the plain file'
    complete -x -c $cmd -n "$when" -s f -l folder -a '(__fish_complete_directories)'
    complete -x -c $cmd -n "$when" -s a -l attributes \
        -a '(__caran_dycrypt_attributes)' -d 'Attributes of the chezmoi source file'
    complete -f -c $cmd -n "$when" -s F -l force \
        -d 'Run even when the output file is already up to date'
    complete -f -c $cmd -n "$when" -n '__fish_seen_subcommand_from encrypt' -s r -l remove \
        -d 'Remove source file after encryption'
    complete -f -c $cmd -n "$when" -s h -l help -d 'Show help'
end
