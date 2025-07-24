-- lua/rich/plugins/lsp.lua
return {
  "neovim/nvim-lspconfig",
  config = function()
    local lspconfig = require("lspconfig")

    -- Example basic server setup
    lspconfig.lua_ls.setup({})
    lspconfig.pyright.setup({})
    lspconfig.rust_analyzer.setup({})

    -- Diagnostic symbols in the sign column
    local signs = { Error = " ", Warn = " ", Hint = "󰌶", Info = " " }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    end
  end,
}
