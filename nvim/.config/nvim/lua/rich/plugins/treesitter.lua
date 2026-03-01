-- Treesitter: syntax-aware highlighting, indentation, and code navigation.
-- Parsers are auto-installed on first encountering a filetype.
-- Textobjects add motions like vaf (select a function), ]m (next method),
-- and <leader>a to swap function arguments.
-- Context shows the current function/class at the top of the window when scrolling.
return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        event = { "BufReadPost", "BufNewFile" },
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
        },
        config = function()
            local ok, configs = pcall(require, "nvim-treesitter.configs")
            if not ok then
                return
            end

            configs.setup({
                ensure_installed = {
                    "lua", "vim", "vimdoc", "bash", "markdown", "markdown_inline",
                    "html", "css", "json", "yaml", "toml", "query",
                    "javascript", "typescript", "python", "rust", "c", "go",
                },
                highlight = { enable = true },
                indent = { enable = true },
                auto_install = true,

                textobjects = {
                    select = {
                        enable = true,
                        lookahead = true,
                        keymaps = {
                            ["af"] = { query = "@function.outer", desc = "Select outer function" },
                            ["if"] = { query = "@function.inner", desc = "Select inner function" },
                            ["ac"] = { query = "@class.outer", desc = "Select outer class" },
                            ["ic"] = { query = "@class.inner", desc = "Select inner class" },
                            ["aa"] = { query = "@parameter.outer", desc = "Select outer argument" },
                            ["ia"] = { query = "@parameter.inner", desc = "Select inner argument" },
                        },
                    },
                    move = {
                        enable = true,
                        set_jumps = true,
                        goto_next_start = {
                            ["]m"] = { query = "@function.outer", desc = "Next function start" },
                            ["]]"] = { query = "@class.outer", desc = "Next class start" },
                        },
                        goto_next_end = {
                            ["]M"] = { query = "@function.outer", desc = "Next function end" },
                            ["]["] = { query = "@class.outer", desc = "Next class end" },
                        },
                        goto_previous_start = {
                            ["[m"] = { query = "@function.outer", desc = "Prev function start" },
                            ["[["] = { query = "@class.outer", desc = "Prev class start" },
                        },
                        goto_previous_end = {
                            ["[M"] = { query = "@function.outer", desc = "Prev function end" },
                            ["[]"] = { query = "@class.outer", desc = "Prev class end" },
                        },
                    },
                    swap = {
                        enable = true,
                        swap_next = {
                            ["<leader>a"] = { query = "@parameter.inner", desc = "Swap with next argument" },
                        },
                        swap_previous = {
                            ["<leader>A"] = { query = "@parameter.inner", desc = "Swap with prev argument" },
                        },
                    },
                },
            })
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        event = { "BufReadPost", "BufNewFile" },
        opts = {},
    },
}
