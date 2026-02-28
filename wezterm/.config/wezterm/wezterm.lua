local wezterm = require 'wezterm'
return {
    -- UI Options
    font_size = 18.0,
    font = wezterm.font_with_fallback({
        "JetBrainsMono Nerd Font",
        "JetBrains Mono",
        "Menlo",
    }),

    color_scheme = "Rosé Pine Moon",
    enable_tab_bar = false,
    window_padding = {
        left = 4, right = 4, top = 4, bottom = 4,
    },

    enable_kitty_keyboard = true,
    scrollback_lines = 10000,
    adjust_window_size_when_changing_font_size = false,

    default_prog = {
        "/opt/homebrew/bin/tmux", "new", "-A", "-s", "main"
    },
}
