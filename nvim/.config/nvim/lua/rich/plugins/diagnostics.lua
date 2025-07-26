    print("Diagnositics.lua setup run")
return {
    "neovim/nvim-lspconfig",
    config = function()
    vim.diagnostic.config({
      virtual_text = {
        spacing = 4,
        prefix = "●",
      },
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
    })
end,
}
