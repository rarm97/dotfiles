print("Mason setup successful")
return {
    {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
    lazy = false,
    priority = 1000,
}
}
