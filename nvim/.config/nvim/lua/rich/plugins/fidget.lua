-- Fidget: shows LSP progress notifications (e.g. "indexing...") in the
-- bottom-right corner. Unobtrusive feedback that servers are working.
return {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {},
}
