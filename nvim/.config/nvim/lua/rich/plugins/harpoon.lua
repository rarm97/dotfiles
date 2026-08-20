-- Harpoon: bookmark up to 4 files for instant switching.
-- Faster than telescope for files you're actively working on.
-- <leader>ha to mark, <leader>hr to remove, <leader>h1-4 to jump, <leader>hh for the menu.
return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },

    -- Declared as lazy `keys` rather than set inside config: with the mappings
    -- in config, lazy had no trigger and loaded harpoon (and plenary) at every
    -- startup whether or not they were used. Same bindings, same behaviour, but
    -- nothing is required until one is pressed.
    keys = {
        { "<leader>ha", function() require("harpoon"):list():add() end,    desc = "Harpoon: Add file" },
        { "<leader>hr", function() require("harpoon"):list():remove() end, desc = "Harpoon: Remove file" },
        { "<leader>hh", function()
            local harpoon = require("harpoon")
            harpoon.ui:toggle_quick_menu(harpoon:list())
        end, desc = "Harpoon: Quick Menu" },

        { "<leader>h1", function() require("harpoon"):list():select(1) end, desc = "Harpoon: Go to file 1" },
        { "<leader>h2", function() require("harpoon"):list():select(2) end, desc = "Harpoon: Go to file 2" },
        { "<leader>h3", function() require("harpoon"):list():select(3) end, desc = "Harpoon: Go to file 3" },
        { "<leader>h4", function() require("harpoon"):list():select(4) end, desc = "Harpoon: Go to file 4" },
    },

    config = function()
        require("harpoon"):setup()
    end,
}
