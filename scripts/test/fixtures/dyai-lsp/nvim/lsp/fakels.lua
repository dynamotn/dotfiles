-- Fixture: the nvim config's own lsp/*.lua override for fakels, exactly like
-- lua/.../lsp/termuxls.lua etc. in the real config.
return {
  cmd = { 'fakels-bin', '--stdio' },
}
