-- ============================================================================
-- ZX Neovim Plugin
-- Provides syntax highlighting, LSP, and file icons for .zx files
-- ============================================================================

-- Register filetype first (critical for LSP)
vim.filetype.add({ extension = { zx = "zx" } })
vim.treesitter.language.register("zx", "zx")

-- ============================================================================
-- Treesitter Parser Setup
-- ============================================================================

local parser_path = vim.fn.stdpath("data") .. "/site/parser/zx.so"

-- Auto-build parser if tree-sitter CLI is available
if vim.fn.filereadable(parser_path) == 0 and vim.fn.executable("tree-sitter") == 1 then
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h")
  local grammar_dir = plugin_dir .. "/../../packages/tree-sitter-zx"
  
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

-- Configure nvim-treesitter parser
local ok, parsers = pcall(require, "nvim-treesitter.parsers")
if ok then
  local config = {
    install_info = {
      url = "https://github.com/nurulhudaapon/zx",
      files = { "packages/tree-sitter-zx/src/parser.c" },
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

-- ============================================================================
-- File Icon Setup
-- ============================================================================

local function setup_file_icon()
  -- Configure nvim-web-devicons
  local ok_devicons, devicons = pcall(require, "nvim-web-devicons")
  if ok_devicons then
    devicons.setup({
      override = {
        zx = {
          icon = "zx ",
          color = "#ff9800",
          cterm_color = "214",
          name = "zx",
        },
      },
      override_by_extension = {
        ["zx"] = {
          icon = "zx ",
          color = "#ff9800",
          cterm_color = "214", 
          name = "zx",
        },
      },
    })
  end
  
  -- Configure mini.icons as fallback
  local ok_mini, mini_icons = pcall(require, "mini.icons")
  if ok_mini then
    mini_icons.setup({
      extension = {
        zx = { glyph = "zx ", hl = "MiniIconsOrange" },
      },
      filetype = {
        zx = { glyph = "zx ", hl = "MiniIconsOrange" },
      },
    })
  end
end

-- Set up icons after a delay to ensure icon plugins are loaded
vim.defer_fn(setup_file_icon, 100)

-- ============================================================================
-- LSP Configuration
-- ============================================================================

local zls_setup_done = false
local buffer_reopened = {}

-- Detect if current workspace is a zx project (has build.zig + site/ directory)
local function is_zx_workspace()
  local cwd = vim.fn.getcwd()
  return vim.fn.filereadable(cwd .. "/build.zig") == 1 
     and vim.fn.isdirectory(cwd .. "/site") == 1
end

-- Custom diagnostic handler to filter ZX-specific false positives
local function custom_diagnostic_handler(err, result, ctx, config)
  if result and result.diagnostics then
    local filtered_diagnostics = {}
    for _, diagnostic in ipairs(result.diagnostics) do
      -- Skip "expected expression, found '<'" errors (ZX tags)
      if not (diagnostic.message and diagnostic.message:match("expected expression, found '<'")) then
        table.insert(filtered_diagnostics, diagnostic)
      end
    end
    result.diagnostics = filtered_diagnostics
  end
  
  vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
end

-- Set up zls LSP for .zx files only (doesn't interfere with .zig files)
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
  
  -- Create separate LSP config for .zx files
  if not configs.zls_zx then
    configs.zls_zx = {
      default_config = {
        cmd = { "zls" },
        filetypes = { "zx" },
        root_dir = lspconfig.util.root_pattern("build.zig", "zls.json", ".git"),
        single_file_support = true,
      },
    }
  end
  
  -- Setup LSP with custom handlers
  lspconfig.zls_zx.setup({
    filetypes = { "zx" },
    root_dir = lspconfig.util.root_pattern("build.zig", "zls.json", ".git"),
    single_file_support = true,
    on_attach = function(client, bufnr)
      -- Enable inlay hints if supported
      if vim.lsp.inlay_hint and client.server_capabilities and client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end
    end,
    handlers = {
      ["textDocument/publishDiagnostics"] = vim.lsp.with(custom_diagnostic_handler, {}),
    },
  })
  
  zls_setup_done = true
  
  -- Attach to any existing .zx buffers
  vim.schedule(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "zx" then
        vim.api.nvim_exec_autocmds("FileType", {
          buffer = buf,
          group = "lspconfig",
          modeline = false,
        })
      end
    end
  end)
  
  return true
end

-- Proactively set up LSP on startup if in a zx workspace
local function proactive_setup()
  vim.schedule(function()
    local success = setup_zls()
    if success and is_zx_workspace() then
      vim.notify("ZX: LSP ready for zx workspace", vim.log.levels.INFO)
    end
  end)
end

-- Run proactive setup after startup
vim.defer_fn(proactive_setup, 200)

-- ============================================================================
-- Autocmds
-- ============================================================================

-- Set up LSP when changing directories
vim.api.nvim_create_autocmd("DirChanged", {
  callback = function()
    if not zls_setup_done then
      proactive_setup()
    end
  end,
})

-- Handle LSP attachment with auto-reopen workaround
-- ZLS needs time to load build.zig, so we detach and reattach after 3 seconds
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= "zls_zx" then
      return
    end
    
    local bufnr = args.buf
    
    -- Auto-reopen logic: only run once per buffer
    if not buffer_reopened[bufnr] then
      buffer_reopened[bufnr] = true
      
      vim.notify("ZX: LSP attached, waiting for build configuration...", vim.log.levels.INFO)
      
      -- Wait for build config to load, then detach and reattach
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        
        -- Detach LSP
        vim.lsp.buf_detach_client(bufnr, client.id)
        
        -- Reattach after brief delay
        vim.defer_fn(function()
          if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "zx" then
            return
          end
          
          vim.api.nvim_exec_autocmds("FileType", {
            buffer = bufnr,
            group = "lspconfig",
            modeline = false,
          })
          
          vim.notify("ZX: LSP reattached, fully ready!", vim.log.levels.INFO)
        end, 500)
      end, 3000) -- 3 second delay for build config loading
    end
  end,
})

-- FileType autocmd for .zx files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "zx",
  callback = function(args)
    -- Start treesitter
    if vim.fn.filereadable(parser_path) == 1 then
      pcall(vim.treesitter.start, args.buf, "zx")
    end
    
    -- Ensure LSP is set up
    if not zls_setup_done then
      local success = setup_zls()
      if not success and vim.fn.executable("zls") == 0 then
        vim.notify("ZX: zls not found. Install zig to get LSP support.", vim.log.levels.WARN)
      end
    end
    
    -- Buffer-local keymaps
    vim.keymap.set("n", "<leader>zh", "<cmd>Inspect<CR>", 
      { buffer = args.buf, desc = "ZX: Show Highlight" })
    vim.keymap.set("n", "<leader>zt", "<cmd>InspectTree<CR>", 
      { buffer = args.buf, desc = "ZX: Inspect Tree" })
  end,
})
