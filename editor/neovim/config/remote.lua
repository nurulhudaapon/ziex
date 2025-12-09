-- ~/.config/nvim/lua/plugins/zx.lua
return {
    "nurulhudaapon/zx",
    dependencies = { 
        "nvim-treesitter/nvim-treesitter",
        "neovim/nvim-lspconfig",  -- for LSP support
    },
    ft = "zx",
    init = function() vim.filetype.add({ extension = { zx = "zx" } }) end,
    config = function()
        vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/zx/editor/neovim")
        vim.cmd("runtime! plugin/zx.lua")
    end,
}
