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

-- Configure zls LSP for .zx files only (not .zig files)
local zls_setup_done = false

local function setup_zls()
  if zls_setup_done then
    return true
  end
  
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    return false
  end

  if vim.fn.executable("zls") == 0 then
    return false
  end

  local configs = require("lspconfig.configs")
  
  -- Create a separate zls config specifically for .zx files
  -- Don't interfere with existing zls setup for .zig files
  if not configs.zls_zx then
    configs.zls_zx = {
      default_config = {
        cmd = { "zls" },
        filetypes = { "zx" },
        root_dir = lspconfig.util.root_pattern("zls.json", "build.zig", ".git"),
        single_file_support = true,
      },
    }
    
    -- Custom diagnostic handler to filter out specific errors
    local function custom_diagnostic_handler(err, result, ctx, config)
      -- Filter out diagnostics before publishing
      if result and result.diagnostics then
        local filtered_diagnostics = {}
        for _, diagnostic in ipairs(result.diagnostics) do
          -- Skip "expected expression, found '<'" errors completely
          if not (diagnostic.message and diagnostic.message:match("expected expression, found '<'")) then
            table.insert(filtered_diagnostics, diagnostic)
          end
        end
        result.diagnostics = filtered_diagnostics
      end
      
      -- Call the default handler with filtered diagnostics
      vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
    end
    
    -- Set up the zls_zx LSP specifically for .zx files
    lspconfig.zls_zx.setup({
      filetypes = { "zx" },
      root_dir = lspconfig.util.root_pattern("zls.json", "build.zig", ".git"),
      single_file_support = true,
      handlers = {
        ["textDocument/publishDiagnostics"] = vim.lsp.with(
          custom_diagnostic_handler,
          {}
        ),
      },
    })
  end
  
  zls_setup_done = true
  return true
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "zx",
  callback = function(args)
    -- Set up treesitter
    if vim.fn.filereadable(parser_path) == 1 then
      pcall(vim.treesitter.start, args.buf, "zx")
    end
    
    -- Try to set up LSP (will only run once)
    vim.schedule(function()
      local success = setup_zls()
      if not success and vim.fn.executable("zls") == 0 and not zls_setup_done then
        vim.notify("ZX: zls not found. Install zig to get LSP support.", vim.log.levels.WARN)
      end
    end)
    
    vim.keymap.set("n", "<leader>zh", "<cmd>Inspect<CR>", 
      { buffer = args.buf, desc = "ZX: Show Highlight" })
    vim.keymap.set("n", "<leader>zt", "<cmd>InspectTree<CR>", 
      { buffer = args.buf, desc = "ZX: Inspect Tree" })
  end,
})
