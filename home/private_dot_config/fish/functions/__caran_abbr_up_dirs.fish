function __caran_abbr_up_dirs --description 'Expand `...` to `../..`, one more level per dot' --argument-names token
    set -l dots (string match -r -- '^\.+' $token)
    set -l rest (string sub -s (math (string length -- $dots) + 1) -- $token)
    string repeat -n (math (string length -- $dots) - 1) -- ../ | string replace -r '/$' -- $rest
end
