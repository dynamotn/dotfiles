-- Fixture for a server whose cmd is a function (built per buffer, e.g.
-- sonarlint/jdtls in the real config); the exporter must skip it.
return {
  cmd = function() end,
  filetypes = { 'fn' },
}
