-- Fixture mirroring the real config.languages shape used by the dyai LSP
-- exporter: per-language filetypes and the lsp_servers each language wants.
return {
  python = { filetypes = { 'python' }, lsp_servers = { 'pyls', 'ruffls' } },
  fake = { filetypes = { 'fake' }, lsp_servers = { 'fakels' } },
  generic = { filetypes = { 'generic' }, lsp_servers = { 'genericls' } },
  fn = { filetypes = { 'fn' }, lsp_servers = { 'fnls' } },
  clike = { filetypes = { 'c', 'cs', 'make', 'sh', 'tex' }, lsp_servers = { 'cls' } },
}
