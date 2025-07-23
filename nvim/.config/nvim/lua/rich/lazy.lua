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

require("lazy").setup({

    -- Ripgrep
    

    -- Plenary
    {"nvim-lua/plenary.nvim"},

    -- Telescope
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { 'nvim-lua/plenary.nvim' },
        config = function()
            require('telescope').setup({
                defaults = {
                    layout_strategy = 'horizontal',
                    layout_config = {
                        prompt_position = "top",
                    },
                    sorting_strategy = "ascending",
                },
            })
        end
    },
    -- Theme
    { "folke/tokyonight.nvim", priority = 1000 },

    -- Treesitter for syntax highlighting
    { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
    { "nvim-treesitter/nvim-treesitter-context" },

    -- LSP
    { "neovim/nvim-lspconfig" },
    { "williamboman/mason.nvim" },
    { "williamboman/mason-lspconfig.nvim" },

    -- Autocompletion
    { "hrsh7th/nvim-cmp" },
    { "hrsh7th/cmp-nvim-lsp" },
    { "L3MON4D3/LuaSnip" },
    { "saadparwaiz1/cmp_luasnip" },

    -- Statusline
    { "nvim-lualine/lualine.nvim" },

    -- Git
    { "tpope/vim-fugitive" },

    -- File nav
    {
    "nvim-tree/nvim-tree.lua",
    dependencies = {"nvim-tree/nvim-web-devicons"}, 
    config = function()
        local maps = require("rich.nvim-tree-keymaps")

        require("nvim-tree").setup({
            on_attach = maps.attach, 
            sync_root_with_cwd = true,
            view = {
                width = 30,
                number = true,
                relativenumber = true,
            },
        })
    end,
    },

    -- ThePrimeagen-style workflow tools
    { "ThePrimeagen/harpoon" },
    { "mbbill/undotree" },
    { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
})

