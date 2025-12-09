-- ~/.config/nvim/lua/plugins/zx.lua
return {
    dir = "/Users/nurulhudaapon/Projects/nurulhudaapon/zx",
    name = "zx",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "neovim/nvim-lspconfig",
    },
    ft = "zx",
    init = function()
        vim.filetype.add({ extension = { zx = "zx" } })
    end,
    config = function()
        vim.opt.runtimepath:prepend("/Users/nurulhudaapon/Projects/nurulhudaapon/zx/editor/neovim")
        vim.cmd("runtime! plugin/zx.lua")
    end,
}
