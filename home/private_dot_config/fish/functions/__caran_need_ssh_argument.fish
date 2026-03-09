# Prevent show when not have argument
function __caran_need_ssh_argument
    set cmd (commandline -opc)
    if test (count $cmd) = 1
        return 1
    else
        set accept_argument -l -r -p
        if contains -- $cmd[-1] $accept_argument
            return 0
        end
        return 1
    end
    return 1
end
