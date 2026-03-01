-- WezTerm terminal emulator configuration.
-- Launches directly into a tmux session (creates or reattaches to "main").
-- Rosé Pine Moon theme to match nvim and tmux.
local wezterm = require 'wezterm'
return {
    font_size = 18.0,
    font = wezterm.font_with_fallback({
        "JetBrainsMono Nerd Font",
        "JetBrains Mono",
        "Menlo",
    }),

    color_scheme = "Rosé Pine Moon",
    enable_tab_bar = false,             -- tmux handles windowing
    window_padding = {
        left = 4, right = 4, top = 4, bottom = 4,
    },

    enable_kitty_keyboard = true,       -- better key reporting for nvim
    scrollback_lines = 10000,
    adjust_window_size_when_changing_font_size = false,

    -- Auto-attach to tmux "main" session (or create it)
    default_prog = {
        "/opt/homebrew/bin/tmux", "new", "-A", "-s", "main"
    },
}
