-- Give every application its own input source: terminals and launchers are
-- always typed in English, any other application gets back the input source it
-- was left with, so Vietnamese in Telegram does not leak into the shell
local M = {}

M.english = 'com.apple.keylayout.USExtended'

local alwaysEnglish = {
  ['net.kovidgoyal.kitty'] = true,
  ['com.vicinaehq.Vicinae'] = true,
}

-- Input source each application was left with, by bundle id
local lastSource = {}
local frontmost = hs.application.frontmostApplication()
local activeApp = frontmost and frontmost:bundleID()

local function selectSource(source)
  if source and source ~= hs.keycodes.currentSourceID() then
    hs.keycodes.currentSourceID(source)
  end
end

-- Only "activated" is used: the order of "deactivated" against it is not
-- guaranteed, so the outgoing application is tracked here instead
M.watcher = hs.application.watcher
  .new(function(_, event, app)
    if event ~= hs.application.watcher.activated or not app then
      return
    end
    local bundleID = app:bundleID()
    if not bundleID then
      return
    end
    if activeApp and not alwaysEnglish[activeApp] then
      lastSource[activeApp] = hs.keycodes.currentSourceID()
    end
    activeApp = bundleID
    selectSource(alwaysEnglish[bundleID] and M.english or lastSource[bundleID])
  end)
  :start()

-- Run fn with the English layout selected, then put the previous source back.
-- The switch reaches the focused application asynchronously, hence the delay;
-- the timer is kept on M so it is not garbage collected before it fires
function M.withEnglish(fn)
  local previous = hs.keycodes.currentSourceID()
  if previous == M.english then
    fn()
    return
  end
  selectSource(M.english)
  M.pending = hs.timer.doAfter(0.1, function()
    M.pending = nil
    fn()
    selectSource(previous)
  end)
end

return M
