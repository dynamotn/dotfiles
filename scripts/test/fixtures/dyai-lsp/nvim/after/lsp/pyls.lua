-- Fixture: the nvim config's after/lsp/*.lua override for a server the
-- fixture nvim-lspconfig dir also ships (lspconfig/lsp/pyls.lua), like the
-- real config's after/lsp/yls.lua. In a live Neovim after/ comes last on the
-- runtimepath, so this cmd must win over the shipped one.
return {
  cmd = { 'pyls-bin', '--from-after' },
}
