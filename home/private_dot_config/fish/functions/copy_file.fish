function copy_file --description 'Copy files with some extra behaviors'
    # A directory is copied recursively, its destination parent created
    if test (count $argv) -eq 2; and test -d "$argv[1]"
        mkdir -p (path dirname $argv[2])
        command cp -i -r (string trim -r -c / -- $argv[1]) $argv[2]
    else
        command cp -i $argv
    end
end
