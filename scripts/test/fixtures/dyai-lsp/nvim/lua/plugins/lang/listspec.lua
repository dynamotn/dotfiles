-- Fixture: the real-world lazy.nvim shape (e.g. the real config's cpp.lua),
-- a *list* of several plugin specs rather than a single one, with the
-- nvim-lspconfig entry among them. Exercises lspconfig_specs_in()'s
-- list-handling branch.
return {
  { 'other/plugin' },
  {
    'neovim/nvim-lspconfig',
    opts = {
      servers = {
        pyls = {
          settings = { listspec = true },
        },
      },
    },
  },
}
