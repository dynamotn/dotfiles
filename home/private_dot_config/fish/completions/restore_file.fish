# restore_file moves a `.bak` copy back over the file it was made from, so sort
# those first. `-k` is what keeps that order: __fish_complete_suffix lists the
# other files too, as a fallback.
complete -k -f -c restore_file -a '(__fish_complete_suffix .bak)'
