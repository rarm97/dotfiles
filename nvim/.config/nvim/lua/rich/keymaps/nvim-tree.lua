
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
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then return end

  api.config.mappings.default_on_attach(bufnr)

  map("<C-[>", api.tree.change_root_to_parent, "Up one directory", bufnr)
  map("o", api.node.open.edit, "Open File", bufnr)
  map("v", api.node.open.vertical, "Open Vertical", bufnr)
  map("s", api.node.open.horizontal, "Open Horizontal", bufnr)
end

return M

