-- Fixture for a generic, non-language server; it is dropped via the
-- global.lsp.exclude list, not by anything in this file.
return {
  cmd = { 'genericls-bin' },
  filetypes = { 'generic' },
}
