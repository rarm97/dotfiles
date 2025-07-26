return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
    lazy = false,
    priority = 1000,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    priority = 900,
  }
}
