function is_symlink --argument file --description "Test file is link or not"
    test -L (string trim -r -c / -- $file)
end
