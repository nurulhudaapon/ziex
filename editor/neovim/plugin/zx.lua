vim.treesitter.language.register('zx', 'zx')

local parser_path = vim.fn.stdpath("data") .. "/site/parser/zx.so"

if vim.fn.filereadable(parser_path) == 0 and vim.fn.executable("tree-sitter") == 1 then
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h")
  local grammar_dir = plugin_dir .. "/../../tree-sitter-zx"
  
  vim.notify("ZX: Building parser...", vim.log.levels.INFO)
  vim.fn.mkdir(vim.fn.stdpath("data") .. "/site/parser", "p")
  
  local cmd = string.format("cd %s && tree-sitter build --output %s", 
    vim.fn.shellescape(grammar_dir), vim.fn.shellescape(parser_path))
  vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
    vim.notify("ZX: Parser built successfully!", vim.log.levels.INFO)
  else
    vim.notify("ZX: Build failed. Run: cd " .. grammar_dir .. " && tree-sitter build --output " .. parser_path, vim.log.levels.ERROR)
  end
elseif vim.fn.filereadable(parser_path) == 0 then
  vim.notify("ZX: Install tree-sitter CLI (brew install tree-sitter)", vim.log.levels.WARN)
end

local ok, parsers = pcall(require, "nvim-treesitter.parsers")
if ok then
  local config = {
    install_info = {
      url = "https://github.com/nurulhudaapon/zx",
      files = {"tree-sitter-zx/src/parser.c"},
      branch = "main",
      generate_requires_npm = false,
    },
    filetype = "zx",
  }
  
  if parsers.get_parser_configs then
    parsers.get_parser_configs().zx = config
  else
    parsers.zx = config
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "zx",
  callback = function(args)
    if vim.fn.filereadable(parser_path) == 1 then
      pcall(vim.treesitter.start, args.buf, "zx")
    end
    
    vim.keymap.set("n", "<leader>zh", "<cmd>Inspect<CR>", 
      { buffer = args.buf, desc = "ZX: Show Highlight" })
    vim.keymap.set("n", "<leader>zt", "<cmd>InspectTree<CR>", 
      { buffer = args.buf, desc = "ZX: Inspect Tree" })
  end,
})
