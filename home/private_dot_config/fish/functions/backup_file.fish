function backup_file --argument filename --description 'Backup file'
    cp $filename $filename.bak
end
