
return {
    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons",
            "MunifTanjim/nui.nvim",
        },
        keys = {
            { "<C-n>", "<cmd>Neotree toggle<cr>", desc = "Neo-tree toggle" },
        },
        config = function()
            require("neo-tree").setup({
                close_if_last_window = true,

                default_component_configs = {
                    indent = { padding = 0 },
                    icon = {
                        folder_closed = "",
                        folder_open = "",
                        folder_empty = "",
                        default = "󰈙",
                    },
                    git_status = {
                        symbols = {
                            added     = "✚",
                            modified  = "",
                            deleted   = "✖",
                            renamed   = "󰁕",
                            untracked = "",
                            ignored   = "",
                            unstaged  = "󰄱",
                            staged    = "",
                            conflict  = "",
                        },
                    },
                },

                filesystem = {
                    follow_current_file = { enabled = true },
                    use_libuv_file_watcher = true,

                    filtered_items = {
                        hide_dotfiles = false,
                        hide_gitignored = false,
                        never_show = { ".DS_Store" },
                    },

                    -- Keep it clean: show git status, but don’t add extra columns/noise
                    components = {
                        name = function(config, node, state)
                            local name = require("neo-tree.sources.filesystem.components").name
                            config.highlight = config.highlight or "NeoTreeFileName"
                            return name(config, node, state)
                        end,
                    },
                },

                -- Neo-tree can show git status without turning into a Christmas tree
                window = {
                    width = 34,
                    mappings = {
                        ["<space>"] = "none", -- reduce accidental toggles
                    },
                },
            })
        end,
    },

    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns").setup({
                signcolumn = true,
                numhl = false,
                linehl = false,
                current_line_blame = false,
            })
        end,
    },
}

