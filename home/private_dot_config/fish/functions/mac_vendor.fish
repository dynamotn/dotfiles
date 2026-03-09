function mac_vendor --description "Display MAC address vendor"
    if test -z "$argv"
        echo "Must have MAC address"
        return 1
    end
    curl -s https://api.macvendors.com/(string escape --style=url $argv)
end
