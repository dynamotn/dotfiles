function copy_file --description 'Copy files with some extra behaviors'
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | sed "s#/\$##")
        set to (echo $argv[2])
        mkdir -p (basename $to)
        command cp -i -r $from $to
    else
        command cp -i $argv
    end
end
