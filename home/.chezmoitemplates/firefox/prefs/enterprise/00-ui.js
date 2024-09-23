{{- if and (eq .place "office") }}
{{- $source := -1.0 }}
{{- if eq .kind "pc" }}
{{- $source = 1.1 }}
{{- end }}
/* Setting the font size of entire UI */
user_pref("layout.css.devPixelsPerPx", {{ $source | quote }});
{{- end }}
