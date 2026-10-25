-- Fixture mirroring the real plugin/review.lua: holds a pattern, then blows
-- up on a module the fixture does not provide, to prove the exporter's
-- `pcall(dofile, ...)` still keeps the pattern recorded before the error.
require('util.untrusted').hold_pattern('^(.*/%.worktrees/dyreview%-[^/]+)')
require('this.module.does.not.exist')
