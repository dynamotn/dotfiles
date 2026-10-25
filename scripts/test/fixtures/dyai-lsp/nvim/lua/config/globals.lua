-- Fixture: a config.globals that errors while loading (the real config's
-- globals.lua sets up `DyNeo`, which the real lang/*.lua specs gate on), to
-- prove the exporter logs it to stderr, keeps going, and still exports a
-- manifest.
error('globals.lua fixture: intentionally fails to load')
