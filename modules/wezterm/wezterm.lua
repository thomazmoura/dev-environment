-- =====================================================================
--  WezTerm — hosts tmux, same role as modules/ghostty/config.
--  Symlinked to ~/.wezterm.lua by LinuxDevEnv/host-setup.sh
-- =====================================================================
local wezterm = require 'wezterm'
local mux = wezterm.mux
local act = wezterm.action

wezterm.on('gui-startup', function(cmd)
  local _, _, window = mux.spawn_window(cmd or {})
  local gui = window:gui_window()
  gui:maximize()
  gui:toggle_fullscreen()
end)

wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local index = ''
  if #tabs > 1 then
    index = string.format('[%d/%d] ', tab.tab_index + 1, #tabs)
  end

  return 'wezterm ' .. index .. tab.active_pane.title
end)

-- The background image lives outside this repo, so the image layer is
-- only added when it is actually present. Everywhere else the gradient
-- stands on its own.
local background = {}

local background_image = wezterm.home_dir .. '/code/LinuxResources/Windows/Images/GeneratedAILinuxHacker.jpg'
local image_handle = io.open(background_image, 'r')
if image_handle ~= nil then
  image_handle:close()
  table.insert(background, {
    source = { File = background_image },
    height = "200%",
    width = "120%",
    horizontal_align = "Right",
    vertical_align = "Middle",
    vertical_offset = "-30",
  })
end

table.insert(background, {
  source = {
    Gradient = {
      colors = {
        '#0f0c29',
        '#302b63',
        '#24243e',
      },
    }
  },
  opacity = .9,
  repeat_x = 'NoRepeat',
  height = "100%",
  width = "100%"
})

return {
  animation_fps = 24,
  audible_bell = "Disabled",
  background = background,
  default_prog = { "pwsh", "-C", "vtmux" },
  enable_tab_bar = false,
  initial_cols = 180,
  initial_rows = 50,
  font = wezterm.font_with_fallback {
    'Cascadia Code',
    'CaskaydiaCoveNerdFont',
  },
  font_size = 12,
  keys = {
    { key = 'N', mods = 'SHIFT|CTRL', action = act.SpawnTab { DomainName = 'local' } },
  },
  underline_position = '-1px',
  underline_thickness = '2px',
  window_close_confirmation = "NeverPrompt",
  window_padding = {
    left = '2px',
    right = '0',
    top = '0',
    bottom = '0',
  },
}
