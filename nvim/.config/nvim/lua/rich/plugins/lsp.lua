return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    -- "hrsh7th/cmp-nvim-lsp", -- if you want cmp completion
  },
  config = function()
    print("===Entered LSP config function===")
    local lspconfig = require("lspconfig")
    local mason_lspconfig = require("mason-lspconfig")
    -- local capabilities = vim.lsp.protocol.make_client_capabilities()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    local on_attach = function(client, bufnr)
      -- Format on save
      if client.server_capabilities.documentFormattingProvider then
        vim.api.nvim_create_autocmd("BufWritePre", {
          buffer = bufnr,
          callback = function()
            vim.lsp.buf.format({ bufnr = bufnr })
          end,
        })
      end
      -- (Other keymaps if you want)
    end

    local servers = {
      "lua_ls",
      "pyright",
      "rust_analyzer",
      "ts_ls", -- NOT "ts_ls"
      "jsonls",
    }

    mason_lspconfig.setup({
      ensure_installed = servers,
      automatic_installation = true,
      handlers = {
        function(server_name)
          print("Attempting to setup:", server_name)
          lspconfig[server_name].setup({
            on_attach = on_attach,
            capabilities = capabilities,
          })
        end,
      },
    })

    -- Diagnostic signs
    local signs = { Error = " ", Warn = " ", Hint = "󰌶", Info = " " }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
    end
  end,
}
