function move_file --description "Move file with some extra behaviors"
    # `mv link/` moves the directory the link points to, not the link
    if is_symlink $argv[1]; and string match -q -- '*/' $argv[1]
        echo "move_file: '$argv[1]' is a symlink with a trailing slash." >&2
        echo "move_file: to rename the symlink, drop the trailing slash." >&2
        return 1
    end
    command mv -i $argv
end
