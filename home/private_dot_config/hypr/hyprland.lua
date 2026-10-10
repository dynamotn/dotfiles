-- Hyprland configuration, split into modules under hyprland/. Each `require`
-- runs in its own scope, so an error in one module does not stop the others.
-- The API stubs live in /usr/share/hypr/stubs for editor completion.
require("hyprland.env")
require("hyprland.core")
require("hyprland.monitor")
require("hyprland.autostart")
require("hyprland.workspace")
require("hyprland.rule")
require("hyprland.binding")
