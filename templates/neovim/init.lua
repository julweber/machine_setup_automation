-- =============================================================================
-- Neovim Configuration
-- Based on lazy.nvim + nvim-lspconfig setup
-- Template file - copied to ~/.config/nvim/init.lua during setup
-- =============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
                  "https://github.com/folke/lazy.nvim.git",
                  "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- =============================================================================
-- Plugin Specifications (lazy.nvim)
-- =============================================================================
local plugins = {
  -- ==================== Core Plugins ====================
  
  -- Telescope: Fuzzy finder (replaces fzf)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          file_ignore_patterns = { ".git", "node_modules", "vendor" },
          mappings = {
            i = { ["<C-j>"] = "move_selection_next",
                   ["<C-k>"] = "move_selection_previous" },
            n = { ["<C-j>"] = "move_selection_next",
                  ["<C-k>"] = "move_selection_previous" },
          },
        },
      })
    end,
  },

  -- ==================== LSP Support ====================
  
  -- nvim-lspconfig: Configuration for language servers
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      
      -- Enable formatting on save
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*",
        callback = function()
          if vim.lsp.buf.format then
            vim.lsp.buf.format({ async = false })
          end
        end,
      })
      
      -- Default LSP setup with common servers
      local servers = { "clangd", "lua_ls", "bashls", "html", "cssls" }
      for _, server in ipairs(servers) do
        if lspconfig[server] then
          lspconfig[server].setup({})
        end
      end
    end,
  },

  -- ==================== Code Intelligence ====================
  
  -- nvim-cmp: Completion engine (replaces YouCompleteMe)
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",       -- LSP source
      "hrsh7th/cmp-buffer",          -- Buffer words source
      "L3MON4D3/LuaSnip",            -- Snippet engine
      "saadparwaiz1/cmp_luasnip",    -- Luasnip integration
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = {
          { name = "nvim_lsp",           priority = 100 },
          { name = "luasnip",            priority = 80 },
          { name = "buffer",             priority = 50 },
        },
      })
    end,
  },

  -- ==================== UI Enhancements ====================
  
  -- bufferline.nvim: Tab line with buffers
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        highlights = function()
          local colors = vim.api.nvim_get_hl(0, { name = "Normal" })
          return {
            background = { fg = colors.bg },
          }
        end,
      })
    end,
  },

  -- ==================== File Navigation ====================
  
  -- oil.nvim: File explorer (replaces netrw)
  {
    "stevearc/oil.nvim",
      config = function()
      require("oil").setup({
        columns = { "icon", "permissions", "size" },
        skip_file_validation = true,
      })
      vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })
    end,
  },

  -- ==================== Syntax & Highlighting ====================
  
  -- nvim-treesitter: Advanced syntax highlighting and parsing
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    main = "nvim-treesitter",
    opts = {
      ensure_installed = { "lua", "vim", "vimdoc" },
      sync_install = false,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },

  -- ==================== Git Integration ====================
  
  -- gitsigns.nvim: Git signs and navigation
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "|" },
        },
      })
    end,
  },
}

-- =============================================================================
-- Lazy Plugin Manager Setup
-- =============================================================================
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require("lazy").setup({
  spec = plugins,
  defaults = { lazy = true },
  install = { colorscheme = { "habamax" } },
  checker = { enabled = false }, -- Disable auto-checking for updates
})

-- =============================================================================
-- General Settings
-- =============================================================================
vim.opt.number = true              -- Show line numbers (1-indexed)
vim.opt.relativenumber = true      -- Relative line numbers
vim.opt.tabstop = 2                -- Tabs are 2 spaces
vim.opt.shiftwidth = 2             -- Indent is 2 spaces
vim.opt.expandtab = true           -- Use spaces instead of tabs
vim.opt.smartindent = true         -- Smart auto-indenting
vim.opt.wrap = false               -- No line wrapping
vim.opt.ignorecase = true          -- Case-insensitive search
vim.opt.smartcase = true           -- Override ignorecase with uppercase
vim.opt.mouse = "a"                -- Mouse support in all modes
vim.opt.termguicolors = true       -- True color support
vim.opt.splitbelow = true          -- New splits go below current line
vim.opt.splitright = true          -- New splits go to the right
vim.opt.showmode = false           -- Don't show mode in status bar
vim.opt.updatetime = 250           -- Faster completion
vim.opt.timeoutlen = 300           -- Shorter timeout for keys
vim.opt.signcolumn = "yes"         -- Always show sign column
vim.opt.scrolloff = 8              -- Lines of context when scrolling
vim.opt.sidescrolloff = 8          -- Columns of context when scrolling
vim.opt.cursorline = true          -- Highlight current line

-- =============================================================================
-- Leader Key Configuration
-- =============================================================================
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- =============================================================================
-- Custom Mappings
-- =============================================================================
-- Toggle relative numbers (useful for navigation)
vim.keymap.set("n", ",r", function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = "Toggle relative numbers" })

-- Better paste: keep register after visual paste
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without overwriting register" })
