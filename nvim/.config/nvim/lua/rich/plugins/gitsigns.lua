-- Gitsigns: shows added/modified/deleted lines in the sign column.
-- Also provides hunk-level staging, resetting, and inline blame.
-- ]c / [c navigate between changed hunks; falls back to diff-mode
-- navigation when in a vimdiff.
return {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
        on_attach = function(bufnr)
            local gs = package.loaded.gitsigns
            local function map(mode, l, r, opts)
                opts = opts or {}
                opts.buffer = bufnr
                vim.keymap.set(mode, l, r, opts)
            end

            map("n", "]c", function()
                if vim.wo.diff then return "]c" end
                vim.schedule(function() gs.next_hunk() end)
                return "<Ignore>"
            end, { expr = true, desc = "Next git hunk" })

            map("n", "[c", function()
                if vim.wo.diff then return "[c" end
                vim.schedule(function() gs.prev_hunk() end)
                return "<Ignore>"
            end, { expr = true, desc = "Prev git hunk" })

            map("n", "<leader>ghs", gs.stage_hunk, { desc = "Stage hunk" })
            map("n", "<leader>ghr", gs.reset_hunk, { desc = "Reset hunk" })
            map("v", "<leader>ghs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Stage hunk" })
            map("v", "<leader>ghr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Reset hunk" })
            map("n", "<leader>ghu", gs.undo_stage_hunk, { desc = "Undo stage hunk" })
            map("n", "<leader>ghp", gs.preview_hunk, { desc = "Preview hunk" })
            map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, { desc = "Blame line" })
            map("n", "<leader>gB", gs.toggle_current_line_blame, { desc = "Toggle line blame" })
        end,
    },
}
