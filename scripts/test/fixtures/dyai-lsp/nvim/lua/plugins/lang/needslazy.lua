-- Fixture: a lang/*.lua spec that requires lazy.nvim at load time, like the
-- real config's lang files through util/plugin.lua. Without lazy.nvim on the
-- runtimepath it fails with a multi-line `module not found` error; with it,
-- its ruffls settings override applies.
local util = require('lazy.core.util')

return {
  'neovim/nvim-lspconfig',
  opts = {
    servers = {
      ruffls = {
        settings = { lazy = util.lazy_marker },
      },
    },
  },
}
