-- Undotree: visual undo history browser.
-- Neovim stores undo as a tree (not linear), so you never lose a state.
-- Pairs with persistent undo (undofile) to survive across sessions.
return {
    "mbbill/undotree",
    keys = {
        { "<leader>u", vim.cmd.UndotreeToggle, desc = "Toggle Undotree" },
    },
}
