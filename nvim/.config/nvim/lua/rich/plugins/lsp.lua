return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
  },
  config = function()
        print("===Entered LSP config function===")
    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    -- No need to call mason.setup() here!
    mason_lspconfig.setup({
      ensure_installed = {
        "lua_ls",
        "pyright",
        "rust_analyzer",
        "ts_ls",
        "jsonls",
      },
      automatic_installation = true,
    })
    -- (rest of your code unchanged)
    local on_attach = function(_, bufnr)
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, {
          buffer = bufnr,
          noremap = true,
          silent = true,
          desc = desc,
        })
      end
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
lspconfig[server_name].setup({
  on_attach = on_attach,
  capabilities = capabilities,
})
      map("n", "gd", vim.lsp.buf.definition, "[LSP] Go to definition")
      map("n", "K", vim.lsp.buf.hover, "[LSP] Hover documentation")
      map("n", "<leader>rn", vim.lsp.buf.rename, "[LSP] Rename symbol")
      map("n", "<leader>ca", vim.lsp.buf.code_action, "[LSP] Code actions")
      map("n", "[d", vim.diagnostic.goto_prev, "[LSP] Previous diagnostic")
      map("n", "]d", vim.diagnostic.goto_next, "[LSP] Next diagnostic")
      map("n", "<leader>d", vim.diagnostic.open_float, "[LSP] Show diagnostic")
      map("n", "gr", vim.lsp.buf.references, "[LSP] References")
    end
    local signs = { Error = " ", Warn = " ", Hint = "󰌶", Info = " " }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    end
    mason_lspconfig.setup({
            handlers = {
      function(server_name)
        print("Attempting to setup: ", server_name)
        lspconfig[server_name].setup({
          on_attach = on_attach,
          capabilities = vim.lsp.protocol.make_client_capabilities(),
        })
      end,
    },
  })
  end,
}
