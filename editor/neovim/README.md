## Installation

```lua
-- ~/.config/nvim/lua/plugins/zx.lua
return {
    "zx",
    dir = "/Users/nurulhudaapon/Projects/nurulhudaapon/zx/editor/neovim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    init = function() vim.filetype.add({ extension = { zx = "zx" } }) end,
    ft = "zx",
}
```