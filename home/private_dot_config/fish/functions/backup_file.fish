function backup_file --description 'Backup file'
    for file in $argv
        command cp $file $file.bak
    end
end
