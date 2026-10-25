-- Fixture: a lazy.nvim-style lang spec overriding fakels' settings, like the
-- real lua/plugins/lang/*.lua specs the exporter reads for cmd/settings overrides.
return {
  'neovim/nvim-lspconfig',
  opts = {
    servers = {
      fakels = {
        settings = { fake = { on = true } },
      },
    },
  },
}
