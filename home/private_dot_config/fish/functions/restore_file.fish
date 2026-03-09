function restore_file --argument filename --description "Restore file"
    mv $filename (echo $filename | sed s/.bak//)
end
