-- Fixture standing in for a C-family server whose filetypes need the
-- exporter's languageId map (cs -> csharp, make -> makefile, ...) and its
-- per-buffer (function-valued) extension handling (.h, .sh, .mk).
return {
  cmd = { 'cls-bin' },
  filetypes = { 'c', 'cs', 'make', 'sh', 'tex' },
}
