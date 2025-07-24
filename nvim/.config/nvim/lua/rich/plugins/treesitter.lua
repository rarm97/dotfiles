
return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "lua", "vim", "bash", "markdown", "markdown_inline",
        "html", "css", "json", "yaml", "toml", "query", "javascript", "python", "rust",
      },
      highlight = { enable = true },
      indent = { enable = true },
      auto_install = true,
    })
  end,
}
