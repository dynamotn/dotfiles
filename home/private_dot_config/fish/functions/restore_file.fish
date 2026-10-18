function restore_file --description "Restore file"
    for file in $argv
        command mv $file (string replace -r '\.bak$' '' -- $file)
    end
end
