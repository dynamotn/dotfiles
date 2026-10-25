-- Exports the language servers Neovim's config already declares into a
-- neutral JSON manifest other AI agents can read. Run headless:
--
--   nvim --clean --headless -l dyai_lsp_export.lua \
--     <nvim_cfg> <lspconfig_dir> <mason_bin> <out_json> <exclude_csv>
--
-- Exits 0 and writes <out_json>, or exits non-zero and writes nothing.
-- See docs/superpowers/specs/2026-10-25-dyai-lsp-design.md §1 for the design.

local nvim_cfg, lspconfig_dir, mason_bin, out_json, exclude_csv = unpack(_G.arg)

if not (nvim_cfg and lspconfig_dir and mason_bin and out_json) then
  io.stderr:write(
    'dyai_lsp_export: usage: <nvim_cfg> <lspconfig_dir> <mason_bin> <out_json> <exclude_csv>\n'
  )
  os.exit(1)
end

local exclude = {}
for name in (exclude_csv or ''):gmatch('[^,]+') do
  exclude[name] = true
end

-- Put the nvim config and nvim-lspconfig on the runtimepath, exactly as a
-- live Neovim would, so `vim.lsp.config[name]` resolves each server's
-- shipped lsp/<name>.lua and the config's own lsp/*.lua / after/lsp/*.lua
-- overrides through Neovim's own lazy-loading.
vim.opt.runtimepath:prepend(lspconfig_dir)
vim.opt.runtimepath:prepend(nvim_cfg .. '/after')
vim.opt.runtimepath:prepend(nvim_cfg)

-- The ERE metacharacters: a `%x` escape only needs a backslash in the
-- output when `x` is one of these; any other punctuation has no special
-- meaning in ERE and comes through literally.
local ERE_SPECIAL = {
  ['.'] = true,
  ['^'] = true,
  ['$'] = true,
  ['*'] = true,
  ['+'] = true,
  ['?'] = true,
  ['('] = true,
  [')'] = true,
  ['['] = true,
  [']'] = true,
  ['{'] = true,
  ['}'] = true,
  ['|'] = true,
  ['\\'] = true,
}

--- Converts a Lua pattern to a POSIX ERE, or nil + a reason when it can't be.
--- `%x` (percent + punctuation) becomes `\x` when `x` is an ERE metacharacter,
--- else just `x`; `.` `*` `+` `?` `[...]` `^` `(` `)` pass through unchanged.
--- A bare `-` outside a bracket class (Lua's lazy quantifier) or a
--- `%a`/`%w`-style class makes the pattern unconvertible.
--- @param pat string
--- @return string|nil ere
--- @return string|nil reason
local function lua_pattern_to_ere(pat)
  local out = {}
  local in_class = false
  local i = 1
  local n = #pat
  while i <= n do
    local c = pat:sub(i, i)
    if c == '%' then
      local nxt = pat:sub(i + 1, i + 1)
      if nxt == '' then
        return nil, 'trailing %% with nothing to escape'
      elseif nxt:match('%p') then
        out[#out + 1] = ERE_SPECIAL[nxt] and ('\\' .. nxt) or nxt
        i = i + 2
      else
        return nil, 'unconvertible class %' .. nxt
      end
    elseif c == '[' then
      in_class = true
      out[#out + 1] = c
      i = i + 1
    elseif c == ']' then
      in_class = false
      out[#out + 1] = c
      i = i + 1
    elseif c == '-' and not in_class then
      return nil, 'unconvertible lazy quantifier -'
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Collects the untrusted-hold Lua patterns from the config's plugin/review.lua,
--- without ever letting the nvim submodule's own code change. `util.untrusted`
--- is stubbed before the file runs, so it only ever records `hold_pattern`
--- calls; the whole load runs under `pcall` so an unrelated error in the file
--- (a module the fixture/sandbox lacks) still leaves earlier calls recorded.
--- @return string[] lua_patterns
local function collect_hold_patterns()
  local patterns = {}
  package.loaded['util.untrusted'] = {
    hold_pattern = function(pat)
      patterns[#patterns + 1] = pat
    end,
  }
  local review_file = nvim_cfg .. '/plugin/review.lua'
  if vim.fn.filereadable(review_file) == 1 then
    pcall(dofile, review_file)
  end
  return patterns
end

--- Builds the manifest's `untrusted_regexes`, dropping and logging any
--- pattern that does not convert.
--- @param lua_patterns string[]
--- @return string[] regexes
local function build_untrusted_regexes(lua_patterns)
  local regexes = {}
  for _, pat in ipairs(lua_patterns) do
    local ere, reason = lua_pattern_to_ere(pat)
    if ere then
      regexes[#regexes + 1] = ere .. '(/|$)'
    else
      io.stderr:write(
        string.format('dyai_lsp_export: dropping untrusted pattern %q (%s)\n', pat, reason)
      )
    end
  end
  return regexes
end

--- Strips a Lua single-line `--` comment off the end of a line and,
--- optionally, the contents of every `'...'`/`"..."` string literal (so a
--- brace or paren inside a flag string like `'{}'` or `'--background-index'`
--- is never mistaken for Lua syntax). Comment detection still sees string
--- contents, so a `--` inside a string never truncates the line early; only
--- `drop_strings` erases them afterwards. Does not handle `--[[ ]]` block
--- comments; languages.lua has none at the top level, where this is applied.
--- @param line string
--- @param drop_strings boolean
--- @return string
local function strip_comment(line, drop_strings)
  local out = {}
  local quote = nil
  local i = 1
  local n = #line
  while i <= n do
    local c = line:sub(i, i)
    if quote then
      if not drop_strings then
        out[#out + 1] = c
      end
      if c == quote then
        quote = nil
      end
      i = i + 1
    elseif c == "'" or c == '"' then
      quote = c
      out[#out + 1] = c
      i = i + 1
    elseif c == '-' and line:sub(i + 1, i + 1) == '-' then
      break
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Scans the raw text of languages.lua for the top-level keys (the language
--- names), in the order they are written. `pairs()` over the loaded table
--- gives no such guarantee — Neovim's Lua randomizes its string-hash seed
--- per process, so hash-based iteration order is not reproducible between
--- runs. Reading the file back out, instead, is what makes "ordered by
--- first appearance in languages.lua" (the manifest's documented contract)
--- actually hold. Scanning starts only at the module's own `return {`
--- (column 0), so an earlier local helper table (`local x = { ... }`)
--- never perturbs the brace count, and stops once that table closes.
--- @param path string
--- @return string[] language names, in file order
local function language_order(path)
  local lines = vim.fn.readfile(path)
  local depth = 0
  local started = false
  local order = {}
  local seen = {}
  for _, raw in ipairs(lines) do
    -- Keeps string contents, for the key regexes (a bracket key's name is a
    -- string literal); a separate, string-stripped pass below feeds the
    -- brace counter so a flag like `'{}'` is never counted as real syntax.
    local line = strip_comment(raw, false)
    if not started then
      if line:match('^return%s*{') then
        started = true
      end
    end
    if started then
      if depth == 1 then
        local key = line:match('^%s*([%a_][%w_]*)%s*=')
          or line:match('^%s*%[%s*[\'"]([^\'"]+)[\'"]%s*%]%s*=')
        if key and not seen[key] then
          seen[key] = true
          order[#order + 1] = key
        end
      end
      for brace in strip_comment(raw, true):gmatch('[{}]') do
        depth = depth + (brace == '{' and 1 or -1)
      end
      if depth == 0 then
        break
      end
    end
  end
  return order
end

--- Loads config.languages and returns, in first-appearance (file) order,
--- each server name plus the union of filetypes every language naming it
--- wants. An entry is a string, or a table whose [1] is the name and whose
--- `filetypes` narrows that language's own filetypes.
--- @return string[] order
--- @return table<string, table<string, boolean>> filetype_sets
local function collect_servers()
  local languages_file = nvim_cfg .. '/lua/config/languages.lua'
  package.path = nvim_cfg .. '/lua/?.lua;' .. nvim_cfg .. '/lua/?/init.lua;' .. package.path
  local ok, languages = pcall(require, 'config.languages')
  if not ok then
    io.stderr:write('dyai_lsp_export: could not load config.languages: ' .. tostring(languages) .. '\n')
    os.exit(1)
  end
  -- Best effort: a config.globals (or similar) that sets up globals like
  -- `DyNeo.enabled_languages` the lang/*.lua specs gate on. Its absence, or
  -- any error in it, is not fatal — the per-file `pcall` in
  -- collect_overrides() already copes with a spec that cannot load.
  pcall(require, 'config.globals')

  local order = {}
  local filetype_sets = {}
  local seen = {}

  for _, lang_name in ipairs(language_order(languages_file)) do
    local lang = languages[lang_name]
    if type(lang) == 'table' then
      local lang_filetypes = lang.filetypes or {}
      for _, entry in ipairs(lang.lsp_servers or {}) do
        local name, filetypes
        if type(entry) == 'table' then
          name = entry[1]
          filetypes = entry.filetypes or lang_filetypes
        else
          name = entry
          filetypes = lang_filetypes
        end
        if name then
          if not seen[name] then
            seen[name] = true
            order[#order + 1] = name
            filetype_sets[name] = {}
          end
          for _, ft in ipairs(filetypes) do
            filetype_sets[name][ft] = true
          end
        end
      end
    end
  end

  return order, filetype_sets
end

--- Collects every table, from `spec` itself or from one of its array
--- entries, whose `[1]` is `neovim/nvim-lspconfig`. A `lua/plugins/lang/*.lua`
--- file may `return` a single plugin spec, or (the common lazy.nvim shape,
--- e.g. the real config's `cpp.lua`) a list of several plugin specs wrapped
--- in a feature-flag `and { ... } or {}` expression.
--- @param spec unknown
--- @return table[] lspconfig_specs
local function lspconfig_specs_in(spec)
  local found = {}
  if type(spec) ~= 'table' then
    return found
  end
  if spec[1] == 'neovim/nvim-lspconfig' then
    found[#found + 1] = spec
    return found
  end
  for _, item in ipairs(spec) do
    if type(item) == 'table' and item[1] == 'neovim/nvim-lspconfig' then
      found[#found + 1] = item
    end
  end
  return found
end

--- Reads every `lua/plugins/lang/*.lua` spec whose `[1]` is
--- `neovim/nvim-lspconfig` and whose `opts` table (or function, called with
--- `{}` under `pcall`) sets `servers.<name>`. Later files win on conflict.
--- @return table<string, table> overrides keyed by server name
local function collect_overrides()
  local overrides = {}
  local glob = nvim_cfg .. '/lua/plugins/lang/*.lua'
  local files = vim.fn.glob(glob, true, true)
  table.sort(files)
  for _, file in ipairs(files) do
    local ok, spec = pcall(dofile, file)
    if ok then
      for _, lspconfig_spec in ipairs(lspconfig_specs_in(spec)) do
        local opts = lspconfig_spec.opts
        if type(opts) == 'function' then
          local opts_ok, resolved = pcall(opts, {})
          opts = opts_ok and resolved or nil
        end
        if type(opts) == 'table' and type(opts.servers) == 'table' then
          for name, server_opts in pairs(opts.servers) do
            if type(server_opts) == 'table' then
              overrides[name] = server_opts
            end
          end
        end
      end
    end
  end
  return overrides
end

--- Resolves cmd[1] to the mason bin if it is executable there, else to
--- whatever `PATH` gives `vim.fn.exepath`. Returns nil when neither resolves.
--- @param bin string
--- @return string|nil
local function resolve_executable(bin)
  local mason_path = mason_bin .. '/' .. bin
  if vim.fn.executable(mason_path) == 1 then
    return mason_path
  end
  local on_path = vim.fn.exepath(bin)
  if on_path ~= '' then
    return on_path
  end
  return nil
end

--- Builds the extensions map for one server: `vim.filetype.inspect().extension`
--- entries whose (string) filetype is one of the server's filetypes, as
--- `"." .. ext"` -> language id. `sh` maps to `shellscript`; function values
--- (per-buffer detection) are ignored.
--- @param filetype_set table<string, boolean>
--- @return table<string, string>
local function build_extensions(filetype_set)
  local extensions = {}
  local by_extension = vim.filetype.inspect().extension or {}
  for ext, ft in pairs(by_extension) do
    if type(ft) == 'string' and filetype_set[ft] then
      local lang_id = ft == 'sh' and 'shellscript' or ft
      extensions['.' .. ext] = lang_id
    end
  end
  return extensions
end

local function sorted_keys(set)
  local keys = {}
  for k in pairs(set) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- `vim.json.encode` renders an empty Lua table as `[]`; the manifest shape
--- needs `{}` for settings/init_options/extensions, so an empty one is
--- forced to encode as an object.
--- @param t table
--- @return table
local function as_object(t)
  if next(t) == nil then
    return vim.empty_dict()
  end
  return t
end

local order, filetype_sets = collect_servers()
local overrides = collect_overrides()
local servers = {}

for _, name in ipairs(order) do
  if not exclude[name] then
    local base = vim.lsp.config[name]
    local override = overrides[name]
    local cmd = (override and override.cmd) or (base and base.cmd)
    if type(cmd) == 'function' then
      io.stderr:write(string.format('dyai_lsp_export: skip %s, cmd is a function\n', name))
    elseif type(cmd) ~= 'table' or cmd[1] == nil then
      io.stderr:write(string.format('dyai_lsp_export: skip %s, no cmd\n', name))
    else
      local resolved = resolve_executable(cmd[1])
      if not resolved then
        io.stderr:write(string.format('dyai_lsp_export: skip %s, %s does not resolve\n', name, cmd[1]))
      else
        local args = {}
        for i = 2, #cmd do
          args[#args + 1] = cmd[i]
        end
        local settings = (override and override.settings) or (base and base.settings) or {}
        local init_options = (override and override.init_options) or (base and base.init_options) or {}
        local filetype_set = filetype_sets[name] or {}
        servers[#servers + 1] = {
          name = name,
          command = resolved,
          args = args,
          filetypes = sorted_keys(filetype_set),
          extensions = as_object(build_extensions(filetype_set)),
          settings = as_object(settings),
          init_options = as_object(init_options),
        }
      end
    end
  end
end

local manifest = {
  version = 1,
  untrusted_regexes = build_untrusted_regexes(collect_hold_patterns()),
  servers = servers,
}

local ok_json, json = pcall(vim.json.encode, manifest)
if not ok_json then
  io.stderr:write('dyai_lsp_export: could not encode manifest: ' .. tostring(json) .. '\n')
  os.exit(1)
end

local fh, err = io.open(out_json, 'w')
if not fh then
  io.stderr:write('dyai_lsp_export: could not write ' .. out_json .. ': ' .. tostring(err) .. '\n')
  os.exit(1)
end
fh:write(json)
fh:close()

os.exit(0)
