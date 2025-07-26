    print("lsp.lua set up run")
return {

  "neovim/nvim-lspconfig",
  dependencies = {
    { "williamboman/mason.nvim" },
    "williamboman/mason-lspconfig.nvim",
  },
  config = function()
    local lspconfig = require("lspconfig")
    local mason = require("mason")
    local mason_lspconfig = require("mason-lspconfig")
    -- Enable mason and ensure essential servers are installed
    mason.setup()
    mason_lspconfig.setup({
      ensure_installed = {
        "lua_ls",
        "pyright",
        "rust_analyzer",
        "tsserver",
        "jsonls",
      },
      automatic_installation = true,
    })

    -- Basic on_attach function
    local on_attach = function(_, bufnr)
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, {
          buffer = bufnr,
          noremap = true,
          silent = true,
          desc = desc,
        })
      end

      map("n", "gd", vim.lsp.buf.definition, "[LSP] Go to definition")
      map("n", "K", vim.lsp.buf.hover, "[LSP] Hover documentation")
      map("n", "<leader>rn", vim.lsp.buf.rename, "[LSP] Rename symbol")
      map("n", "<leader>ca", vim.lsp.buf.code_action, "[LSP] Code actions")
      map("n", "[d", vim.diagnostic.goto_prev, "[LSP] Previous diagnostic")
      map("n", "]d", vim.diagnostic.goto_next, "[LSP] Next diagnostic")
      map("n", "<leader>e", vim.diagnostic.open_float, "[LSP] Show diagnostic")
      map("n", "gr", vim.lsp.buf.references, "[LSP] References")
    end

    local signs = { Error = " ", Warn = " ", Hint = "󰌶", Info = " " }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    end

    mason_lspconfig.setup_handlers({
      function(server_name)
        lspconfig[server_name].setup({
          on_attach = on_attach,
          capabilities = vim.lsp.protocol.make_client_capabilities(),
        })
      end,
    })
  end,
}
