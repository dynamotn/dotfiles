{{/* Include all userscripts in order */}}
{{- $settings := glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/firefox/prefs/*.js") }}
{{- if regexMatch ".*personal/user\\.js\\.tmpl" .chezmoi.sourceFile }}
{{- $settings = concat $settings (glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/firefox/prefs/personal/*.js")) }}
{{- else if regexMatch ".*enterprise/user\\.js\\.tmpl" .chezmoi.sourceFile }}
{{- $settings = concat $settings (glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/firefox/prefs/enterprise/*.js")) }}
{{- else if regexMatch ".*test/user\\.js\\.tmpl" .chezmoi.sourceFile }}
{{- $settings = concat $settings (glob (joinPath .chezmoi.sourceDir ".chezmoitemplates/firefox/prefs/test/*.js")) }}
{{- end }}
{{- $settings = concat $settings (list (joinPath .chezmoi.sourceDir ".chezmoitemplates/firefox/chrome/lepton/user.js")) }}
{{- range ($settings) }}
{{- output "chezmoi" "execute-template" (include .) }}
{{- end }}
