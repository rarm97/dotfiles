local opts = { noremap = true, silent = true }

-- Nvim tree toggle bind. 
vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", opts)

-- Run the current file with python  
vim.keymap.set("n", "<leader>rp", function()
  vim.cmd("w")  -- save the file
  vim.cmd("split | terminal python3 " .. vim.fn.expand("%"))
end, { desc = "Run Python file", noremap = true, silent = true })
    --vim.cmd("w")
   -- vim.cmd("split | terminal python ".. vim.fn.expand("%"))

--end, {desc = "Run python file", noremap = true, silent = true} )

-- Normal mode
-- Save current file
vim.keymap.set("n", "<leader>w", ":w<CR>", opts)
-- Quit current view intelligently (telescope nav can be funny)
vim.keymap.set("n", "<leader>q", function()
    local bt = vim.bo.buftype
    local modifiable = vim.bo.modifiable
    local name = vim.fn.bufname()
    local ft = vim.bo.filetype

    -- If in nvim-tree, close using its API
    if ft == "NvimTree" then
        local ok, api = pcall(require, "nvim-tree.api")
        if ok then
            api.tree.close()
        else
            vim.cmd("q!")
        end
        return
    end

    -- Standard logic for other buffers
    if bt ~= "" or not modifiable or name == "" then
        vim.cmd("q!")
    else
        vim.cmd("q")
    end
end, {desc = "Smart Quit"})

-- Quite current view ad delete buffer 
vim.keymap.set("n", "<leader>x", ":bd<CR>", opts)
-- move down then centre view
vim.keymap.set("n", "j", "jzz", opts)    
-- move up   then centre view
vim.keymap.set("n", "k", "kzz", opts)    

-- Visual mode indentation keeps selection
vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

-- Fast escape
vim.keymap.set("i", "jk", "<Esc>", opts)

-- Git Fugative
vim.keymap.set("n", "<leader>gs", ":Git<CR>", { desc = "Fugitive: Git Status" })

-- Map leader h to nothing for harpoon usage. 
-- vim.keymap.set("n", "<leader>h", "<Nop>", opts)
