-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- collect plugin modules
require("lazy").setup({
  require("rich.plugins.mason"),
    require("rich.plugins.lsp"),-- in your plugin list
{
  "hrsh7th/nvim-cmp",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    -- optional: "hrsh7th/cmp-buffer", "hrsh7th/cmp-path"
  },
  config = function()
    local cmp = require("cmp")
    cmp.setup({
      sources = {
        { name = "nvim_lsp" },
        -- optional: { name = "buffer" }, { name = "path" }
      },
      mapping = cmp.mapping.preset.insert({
        ['<Tab>'] = cmp.mapping.select_next_item(),
        ['<S-Tab>'] = cmp.mapping.select_prev_item(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
      }),
    })
  end,
},
  require("rich.plugins.toggleterm"),
  require("rich.plugins.lazy"), -- lazy.nvim core settings
  require("rich.plugins.telescope"),   -- fuzzy finder
  require("rich.plugins.nvim-tree"),   -- file explorer
  require("rich.plugins.treesitter"),  -- syntax highlighting
  require("rich.plugins.fugitive"),    -- git wrapper
  require("rich.plugins.tokyonight"),   -- display handler
  require("rich.plugins.lualine"),
  require("rich.plugins.harpoon"),
--    require("rich.plugins.diagnostics"),
}) 

