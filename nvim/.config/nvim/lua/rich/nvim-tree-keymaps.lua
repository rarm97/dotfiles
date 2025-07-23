local api = require("nvim-tree.api")

local function map(lhs, rhs, desc, bufnr)
    vim.keymap.set("n", lhs, rhs, {
        desc = "nvim-tree: " .. desc, 
        buffer = bufnr,
        noremap = true,
        silent = true,
        nowait = true,
    })
end

local M = {}

function M.attach(bufnr)
    -- Load default mapping
    api.config.mappings.default_on_attach(bufnr)

    -- Custom keybinds
    map("<C-[>", api.tree.change_root_to_parent, "Up one directory", bufnr)

    map("o", api.node.open.edit, "Open File" , bufnr)
    map("v", api.node.open.vertical, "Open Vertical" , bufnr)
    map("s", api.node.open.horizontal, "Open Horizontal" , bufnr)
end


return M
