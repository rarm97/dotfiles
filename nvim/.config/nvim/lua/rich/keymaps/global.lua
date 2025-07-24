vim.g.mapleader = " "
vim.g.maplocalleader = " "


local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Nvim tree toggle bind. 
keymap("n", "<leader>e", ":NvimTreeToggle<CR>", opts)

-- Normal mode
-- Save current file
keymap("n", "<leader>w", ":w<CR>", opts)
-- Quit current view intelligently (telescope nav can be funny)
vim.keymap.set("n", "<leader>q", function()
    local bt = vim.bo.buftype
    local modifiable = vim.bo.modifiable
    local name = vim.fn.bufname()
    if bt ~= "" or not modifiable or name == "" then
        vim.cmd("q!")
    else
        vim.cmd("q")
    end
end, {desc = "Smart Quit"})

-- Quite current view ad delete buffer 
keymap("n", "<leader>x", ":bd<CR>", opts)
-- move down then centre view
keymap("n", "j", "jzz", opts)    
-- move up   then centre view
keymap("n", "k", "kzz", opts)    

-- Visual mode indentation keeps selection
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

-- Fast escape
keymap("i", "jk", "<Esc>", opts)

-- Git Fugative
vim.keymap.set("n", "<leader>gs", ":Git<CR>", { desc = "Fugitive: Git Status" })
