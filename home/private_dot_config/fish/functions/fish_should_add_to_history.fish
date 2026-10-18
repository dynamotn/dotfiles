function fish_should_add_to_history --description 'Keep commands carrying a credential out of the history' --argument-names cmdline
    # Defining this function replaces the built-in rule, so keep it: a
    # command typed with a leading space stays out of the history.
    string match -q -- ' *' "$cmdline"; and return 1

    set -l name '(?i:token|secret|password|passwd|passphrase|api_?key|access_?key|private_?key)'
    set -l patterns
    # An environment assignment: `GH_TOKEN=… cmd`, `export API_KEY=…`
    set -a patterns '\b[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|PASSPHRASE|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Z0-9_]*=\S'
    # A fish assignment: `set -gx GITLAB_TOKEN …`
    set -a patterns '\bset\s+(-\S+\s+)*[A-Za-z0-9_]*'$name'[A-Za-z0-9_]*\s+\S'
    # A credential handed to a flag: `--password …`, `--token=…`, `--client-secret …`
    set -a patterns '--[a-z-]*'$name'(=|\s+[^\s<|-])'
    # An HTTP authorization header, or a user:password pair in a URL
    set -a patterns '(?i)authorization:\s*(bearer|basic|token)\s'
    set -a patterns '://[^/\s:@]+:[^/\s@]+@'
    # Well-known token shapes: GitHub, GitLab, Slack, AWS, OpenAI and Anthropic style keys
    set -a patterns '\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,})'

    for pattern in $patterns
        string match -qr -- $pattern "$cmdline"; and return 1
    end
    return 0
end
