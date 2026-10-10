local color = require("hyprland.color")

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 2,
    extend_border_grab_area = 4,
    col = {
      active_border = { colors = { color.lavender, color.teal }, angle = 45 },
      inactive_border = color.surface2,
    },

    layout = "dwindle",
    resize_on_border = true,
  },

  decoration = {
    rounding = 10,

    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      new_optimizations = true,
      ignore_opacity = true,
      xray = true,
    },

    active_opacity = 1,
    inactive_opacity = 0.6,
    fullscreen_opacity = 1,

    shadow = {
      enabled = true,
      range = 30,
      render_power = 3,
      color = color.teal,
      color_inactive = color.base,
    },

    dim_inactive = true,
    dim_strength = 0.3,
  },

  animations = {
    enabled = true,
  },

  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "",
    kb_rules = "",

    follow_mouse = 1,

    touchpad = {
      natural_scroll = true,
    },
  },

  group = {
    col = {
      border_inactive = { colors = { color.green, color.yellow }, angle = 45 },
      border_active = { colors = { color.teal, color.green }, angle = 45 },
    },
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },

  dwindle = {
    preserve_split = true,
  },

  cursor = {
    no_hardware_cursors = true,
  },
})

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "loop" })
hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
