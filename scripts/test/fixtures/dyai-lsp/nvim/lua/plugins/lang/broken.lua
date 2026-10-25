-- Fixture: a lang/*.lua spec that errors while loading (not merely returns
-- something unusable), to prove collect_overrides() logs the file and the
-- error to stderr, and keeps processing the other lang/*.lua files.
error('broken.lua fixture: intentionally fails to load')
