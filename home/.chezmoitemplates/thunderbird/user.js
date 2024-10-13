{{/* Include all userscripts in order */}}
{{- $settings := glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/thunderbird/prefs/*.js") }}
{{- if regexMatch ".*personal/user\\.js\\.tmpl" .chezmoi.sourceFile }}
{{- $settings = concat $settings (glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/thunderbird/prefs/personal/*.js")) }}
{{- else if regexMatch ".*enterprise/user\\.js\\.tmpl" .chezmoi.sourceFile }}
{{- $settings = concat $settings (glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/thunderbird/prefs/enterprise/*.js")) }}
{{- end }}
{{- range ($settings) }}
{{- output "chezmoi" "execute-template" (include .) }}
{{- end }}
