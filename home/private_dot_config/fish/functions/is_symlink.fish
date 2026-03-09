function is_symlink --argument file --description "Test file is link or not"
    test -L (echo $file | string replace -r '/$' '' --)
end
