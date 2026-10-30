function ssht --description "Run terminal workspace after ssh"
    argparse -N1 s= -- $argv
    or return
    __caran_remote_workspace "$_flag_s" ssh $argv
end
