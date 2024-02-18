{{- if and (eq .place "office") (eq .kind "pc") }}
/* Setting the font size of entire UI */
user_pref("layout.css.devPixelsPerPx", "1.1");
{{- end }}
