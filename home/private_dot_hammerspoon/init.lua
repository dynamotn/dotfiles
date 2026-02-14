hs.hotkey.bind({ 'cmd', 'ctrl', 'shift' }, 'space', function()
  local englishSource = 'com.apple.keylayout.USExtended'
  local success = hs.keycodes.currentSourceID(englishSource)

  if success then
    hs.alert.show('Keyboard: English', 1)
  else
    hs.alert.show('Error: Could not switch', 1)
  end
end)
