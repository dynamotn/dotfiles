function certp -d 'Print certificate information for a domain'
    set -l domain (string trim $argv)
    if test -z "$domain"
        echo >&2 "Usage: "(status function)" <domain>"
        return 1
    end

    openssl s_client -showcerts -connect $domain:443 -servername $domain </dev/null 2>/dev/null | openssl x509 -text -inform pem -noout
end
