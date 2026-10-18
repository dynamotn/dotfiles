function eat_file --argument dir \
    --description "Moves a directory's contents to the current directory and removes the empty directory"
    if not test -d "$dir"
        echo "eat_file: '$dir' is not a directory" >&2
        return 1
    end

    set -l files $dir/{.,}*
    for f in $files
        set -l name (path basename $f)
        if test -e ./$name
            echo "eat_file: file would be overwritten: ./$name" >&2
            return 1
        end
    end

    command mv $files .; and rmdir $dir
end
