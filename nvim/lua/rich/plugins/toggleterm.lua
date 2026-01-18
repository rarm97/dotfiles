return {
  "akinsho/toggleterm.nvim",
  version = "*",
  config = function()
    require("toggleterm").setup {
      open_mapping = [[<c-\>]],
      direction = "float", -- or "horizontal", "vertical", "tab"
      float_opts = { border = "curved" },
    }
  end
}
