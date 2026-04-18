-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Plugins
vim.pack.add({
	-- LSP
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/mason-org/mason.nvim",
	"https://github.com/mason-org/mason-lspconfig.nvim",
	"https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim",
	"https://github.com/j-hui/fidget.nvim",
	-- Completion
	"https://github.com/saghen/blink.cmp",
	-- Treesitter
	"https://github.com/nvim-treesitter/nvim-treesitter",
	-- File explorer & fuzzy finding
	"https://github.com/stevearc/oil.nvim",
	"https://github.com/ibhagwan/fzf-lua",
	-- Formatting
	"https://github.com/stevearc/conform.nvim",
	-- Git
	"https://github.com/lewis6991/gitsigns.nvim",
	-- UI & editing
	"https://github.com/echasnovski/mini.nvim",
	"https://github.com/echasnovski/mini.icons",
	"https://github.com/folke/which-key.nvim",
	"https://github.com/folke/lazydev.nvim",
	-- Markdown
	"https://github.com/MeanderingProgrammer/render-markdown.nvim",
	-- Theme
	"https://github.com/ember-theme/nvim",
})

-- Options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.showmode = false
vim.opt.clipboard = "unnamedplus"
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.inccommand = "split"
vim.opt.cursorline = true
vim.opt.scrolloff = 10
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.confirm = true
vim.opt.wrap = false
vim.opt.autoread = true

-- Keymaps

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic quickfix" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus left" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus right" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus down" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus up" })

-- Theme
require("ember").setup({ transparent = true })
vim.cmd.colorscheme("ember")

vim.api.nvim_set_hl(0, "MiniStatuslineModeNormal",  { bg = "#e08060", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineModeInsert",  { bg = "#8a9868", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineModeVisual",  { bg = "#7890a0", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineModeReplace", { bg = "#b07878", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineModeCommand", { bg = "#c8b468", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineModeOther",   { bg = "#e08060", fg = "#1c1b19", bold = true })
vim.api.nvim_set_hl(0, "MiniStatuslineFileinfo",    { bg = "#e08060", fg = "#1c1b19" })

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		(vim.hl or vim.highlight).on_yank()
	end,
})

-- Wrap in markdown only
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		vim.opt_local.wrap = true
	end,
})

-- Auto-reload files changed outside Neovim
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})

-- Diagnostics
vim.diagnostic.config({
	severity_sort = true,
	float = { border = "rounded", source = "if_many" },
	underline = { severity = vim.diagnostic.severity.ERROR },
	virtual_text = { source = "if_many", spacing = 2 },
})

-- UI
require("which-key").setup({
	spec = {
		{ "<leader>c", group = "Code" },
		{ "<leader>s", group = "Search" },
		{ "<leader>p", group = "Projects" },
	},
})

local projects = {
	a = { path = "~/Developer/allegro", desc = "allegro" },
	c = { path = "~/Developer/configuration", desc = "configuration" },
	s = { path = "~/Developer/ssl", desc = "ssl" },
	o = { path = "~/Developer/other", desc = "other" },
}
for key, proj in pairs(projects) do
	vim.keymap.set("n", "<leader>p" .. key, function()
		vim.fn.chdir(vim.fn.expand(proj.path))
		require("fzf-lua").files()
	end, { desc = proj.desc })
end
require("mini.ai").setup({ n_lines = 500 })
require("mini.surround").setup()
require("mini.pairs").setup()
require("mini.icons").setup()
require("mini.statusline").setup({ use_icons = true })
require("fidget").setup({})

-- File Navigation
require("oil").setup({
	default_file_explorer = true,
	view_options = { show_hidden = true },
	keymaps = { ["q"] = "actions.close" },
})

local fzf = require("fzf-lua")
fzf.setup({ grep = { cmd = "grep -r -n --color=never", silent = true } })

vim.keymap.set("n", "<leader>sh", fzf.help_tags, { desc = "Search help" })
vim.keymap.set("n", "<leader>sk", fzf.keymaps, { desc = "Search keymaps" })
vim.keymap.set("n", "<leader>sf", fzf.files, { desc = "Search files" })
vim.keymap.set("n", "<leader>sw", fzf.grep_cword, { desc = "Search word" })
vim.keymap.set("n", "<leader>sg", fzf.live_grep, { desc = "Search grep" })
vim.keymap.set("n", "<leader>sd", fzf.diagnostics_document, { desc = "Search diagnostics" })
vim.keymap.set("n", "<leader>ss", fzf.lsp_workspace_symbols, { desc = "Search symbols" })
vim.keymap.set("n", "<leader>sr", fzf.resume, { desc = "Search resume" })
vim.keymap.set("n", "<leader>s.", fzf.oldfiles, { desc = "Search recent files" })
vim.keymap.set("n", "<leader><leader>", fzf.buffers, { desc = "Search buffers" })
vim.keymap.set("n", "<leader>/", fzf.blines, { desc = "Fuzzy search buffer" })

-- Git
require("gitsigns").setup({
	signs = {
		add = { text = "+" },
		change = { text = "~" },
		delete = { text = "_" },
		topdelete = { text = "‾" },
		changedelete = { text = "~" },
	},
})

-- Markdown
require("render-markdown").setup({})

-- LSP
require("lazydev").setup({
	library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
})

require("blink.cmp").setup({
	keymap = { preset = "default" },
	appearance = { nerd_font_variant = "mono" },
	completion = { documentation = { auto_show = false, auto_show_delay_ms = 500 } },
	sources = {
		default = { "lsp", "path", "snippets", "lazydev" },
		providers = { lazydev = { module = "lazydev.integrations.blink", score_offset = 100 } },
	},
	snippets = { preset = "default" },
	fuzzy = { implementation = "lua" },
	signature = { enabled = true },
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
	callback = function(event)
		local map = function(keys, func, desc)
			vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end
		map("gd", fzf.lsp_definitions, "Goto definition")
		map("gr", fzf.lsp_references, "Goto references")
		map("gi", fzf.lsp_implementations, "Goto implementation")
		map("gD", vim.lsp.buf.declaration, "Goto declaration")
		map("<leader>ca", vim.lsp.buf.code_action, "Code action")
		map("<leader>cr", vim.lsp.buf.rename, "Code rename")
		map("<leader>cd", fzf.lsp_typedefs, "Code type definition")
		map("<leader>cs", fzf.lsp_document_symbols, "Code symbols")

		local client = vim.lsp.get_client_by_id(event.data.client_id)
		if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
			local group = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = group,
				callback = vim.lsp.buf.document_highlight,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = group,
				callback = vim.lsp.buf.clear_references,
			})
		end
	end,
})

vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
vim.lsp.config("lua_ls", { settings = { Lua = { completion = { callSnippet = "Replace" } } } })

require("mason").setup()
require("mason-tool-installer").setup({
	ensure_installed = {
		"lua-language-server",
		"stylua",
		"typescript-language-server",
		"bash-language-server",
		"clangd",
		"html-lsp",
		"css-lsp",
		"eslint-lsp",
		"prettier",
	},
})
require("mason-lspconfig").setup({ automatic_enable = true })

vim.lsp.enable("eslint")
vim.lsp.enable("sourcekit") -- Swift; not mason-managed, uses system Xcode toolchain

-- Formatting
require("conform").setup({
	notify_on_error = false,
	format_on_save = { timeout_ms = 500, lsp_fallback = true },
	formatters_by_ft = {
		lua = { "stylua" },
		javascript = { "prettier" },
		typescript = { "prettier" },
		javascriptreact = { "prettier" },
		typescriptreact = { "prettier" },
		json = { "prettier" },
		jsonc = { "prettier" },
	},
})

-- Treesitter
vim.api.nvim_create_autocmd("FileType", {
	callback = function()
		pcall(vim.treesitter.start)
	end,
})
require("nvim-treesitter").setup({
	ensure_installed = {
		"bash",
		"c",
		"css",
		"diff",
		"html",
		"javascript",
		"lua",
		"luadoc",
		"markdown",
		"markdown_inline",
		"query",
		"regex",
		"swift",
		"tsx",
		"typescript",
		"vim",
		"vimdoc",
	},
	auto_install = true,
	highlight = { enable = true },
	indent = { enable = true },
})
