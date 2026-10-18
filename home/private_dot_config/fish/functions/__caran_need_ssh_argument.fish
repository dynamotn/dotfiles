# Offer the common ports only right after a port flag
function __caran_need_ssh_argument
    set -l cmd (commandline -opc)
    test (count $cmd) -gt 1; and contains -- $cmd[-1] -l -r -p
end
