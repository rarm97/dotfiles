-- ~/.wezterm.lua
local wezterm = require 'wezterm'

return {
    font_size = 14.0,
    color_scheme = "Tokyo Night Storm",

    use_fancy_tab_bar = false,
    hide_tab_bar_if_only_one_tab = true,
    enable_tab_bar = false,
    window_padding = {
        left = 4, right = 4, top = 4, bottom = 4,
    },

    enable_kitty_keyboard = true, 
    set_environment_variables = {
        TERM = "xterm-256color",
    }, 

    default_prog = { "/bin/zsh", "-lc", "tmux new -A -s main" }, 

}

