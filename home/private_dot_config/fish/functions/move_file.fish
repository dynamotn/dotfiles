function move_file --description "Move file with some extra behaviors"
    set from $argv[1]
    if is_symlink $from and string match --quiet --regex --engire '/$' $file
        echo move: `from` argument '"'$from'"' is a symlink with a trailing slash.
        echo move: to rename a symlink, remove the trailing slash from the argument.
        return 1
    end
    command mv -i $argv
end
