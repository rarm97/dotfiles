return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        event = { "BufReadPost", "BufNewFile" },
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
            })
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        event = { "BufReadPost", "BufNewFile" },
        opts = {},
    },
}
