-- Fugitive: full git UI inside Neovim.
-- Lazy-loaded on <leader>gs or any :Git command.
return {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gread", "Gwrite", "Gblame", "Glog" },
    keys = {
        { "<leader>gs", "<cmd>Git<cr>", desc = "Fugitive: Git Status" },
    },
}
