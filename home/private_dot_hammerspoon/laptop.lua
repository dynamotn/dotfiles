-- Laptop conveniences: keep the display awake on demand, a global microphone
-- mute, and never let audio burst out of the built-in speakers by surprise
local M = {}

local hyper = { 'ctrl', 'alt', 'cmd' }
local sketchybar = '/opt/homebrew/bin/sketchybar'

-- Show or hide an indicator item declared in sketchybar/items/indicators.sh
local function indicator(item, on)
  if hs.fs.attributes(sketchybar) then
    hs.task.new(sketchybar, nil, { '--set', item, 'drawing=' .. (on and 'on' or 'off') }):start()
  end
end

------------------------------------------------------------------------------
-- Caffeinate
------------------------------------------------------------------------------
function M.toggleCaffeinate()
  local on = hs.caffeinate.toggle('displayIdle')
  hs.alert.show(on and 'Caffeinate: on' or 'Caffeinate: off', 1)
  indicator('caffeinate', on)
end

------------------------------------------------------------------------------
-- Microphone
------------------------------------------------------------------------------
-- Input volume to restore, by device uid, for devices without a mute control
local savedInputVolume = {}

local function micMuted(device)
  local muted = device:inputMuted()
  if muted ~= nil then
    return muted
  end
  return (device:inputVolume() or 0) == 0
end

local function setMicMuted(device, muted)
  if device:setInputMuted(muted) then
    return true
  end
  local uid = device:uid() or ''
  if muted then
    savedInputVolume[uid] = device:inputVolume()
    return device:setInputVolume(0)
  end
  return device:setInputVolume(savedInputVolume[uid] or 75)
end

function M.toggleMic()
  local device = hs.audiodevice.defaultInputDevice()
  if not device then
    hs.alert.show('No microphone', 1)
    return
  end
  local muted = not micMuted(device)
  if not setMicMuted(device, muted) then
    hs.alert.show('Cannot mute ' .. (device:name() or 'microphone'), 2)
    return
  end
  hs.alert.show(muted and 'Microphone: muted' or 'Microphone: live', 1)
  indicator('mic', muted)
end

------------------------------------------------------------------------------
-- Speakers
------------------------------------------------------------------------------
-- Headphones show up as their own device on Apple silicon and as a jack on the
-- built-in device on Intel, so both are ruled out
local function onSpeakers(device)
  if not device or device:transportType() ~= 'Built-in' then
    return false
  end
  if device:jackConnected() then
    return false
  end
  return not (device:name() or ''):find('Headphones')
end

local function muteOutput()
  local device = hs.audiodevice.defaultOutputDevice()
  if device then
    device:setOutputMuted(true)
  end
end

local wasOnSpeakers = onSpeakers(hs.audiodevice.defaultOutputDevice())

-- Mute when the output falls back to the speakers, as when headphones are
-- unplugged or AirPods disconnect, and keep the mic indicator on the device
hs.audiodevice.watcher.setCallback(function(event)
  if event == 'dOut' then
    local nowOnSpeakers = onSpeakers(hs.audiodevice.defaultOutputDevice())
    if nowOnSpeakers and not wasOnSpeakers then
      muteOutput()
      hs.alert.show('Speakers muted', 1)
    end
    wasOnSpeakers = nowOnSpeakers
  elseif event == 'dIn ' then
    local device = hs.audiodevice.defaultInputDevice()
    indicator('mic', device ~= nil and micMuted(device))
  end
end)
hs.audiodevice.watcher.start()

-- Locking or sleeping mutes the output, so nothing plays when the lid opens
M.sleepWatcher = hs.caffeinate.watcher
  .new(function(event)
    local watcher = hs.caffeinate.watcher
    if event == watcher.screensDidLock or event == watcher.systemWillSleep then
      muteOutput()
    end
  end)
  :start()

hs.hotkey.bind(hyper, 'c', M.toggleCaffeinate)
hs.hotkey.bind(hyper, 'm', M.toggleMic)

-- A reload drops every sleep prevention, so bring sketchybar in line
indicator('caffeinate', hs.caffeinate.get('displayIdle'))
local input = hs.audiodevice.defaultInputDevice()
indicator('mic', input ~= nil and micMuted(input))

return M
