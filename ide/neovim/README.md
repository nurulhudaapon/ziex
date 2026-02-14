## Installation

```lua
-- ~/.config/nvim/lua/plugins/zx.lua
return {
    "nurulhudaapon/ziex",
    dependencies = { 
        "nvim-treesitter/nvim-treesitter",
        "neovim/nvim-lspconfig",  -- for LSP support
        "nvim-tree/nvim-web-devicons",  -- for file icons
    },
    -- Load on startup for immediate LSP and icon support
    lazy = false,
    priority = 50,
    config = function()
        vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/zx/ide/neovim")
        vim.cmd("runtime! plugin/zx.lua")
    end,
}
```