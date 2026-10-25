-- Fixture standing in for nvim-lspconfig's shipped lsp/ruffls.lua. The real
-- ruff-lsp binary is named `ruff-bin` here, deliberately not `ruffls-bin`.
return {
  cmd = { 'ruff-bin' },
  filetypes = { 'python' },
}
