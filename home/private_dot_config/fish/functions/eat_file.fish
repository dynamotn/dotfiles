function eat_file --argument dir \
    --description "Moves a directory's contents to the current directory and removes the empty directory"
    set files_to_move (find $dir -maxdepth 1 -not -path $dir)

    for f in $files_to_move
        set filename (echo $f | string replace $dir '' | trim-left /)
        if test -e ./$filename
            echo "eat: file would be overwritten: ./$filename"
            return 1
        end
    end

    set target (dirname $dir)

    for f in $files_to_move
        mv $f $target
    end

    rmdir $dir
end
