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
	"https://github.com/supermaven-inc/supermaven-nvim",
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
	"https://github.com/folke/flash.nvim",
	"https://github.com/MeanderingProgrammer/render-markdown.nvim",
	-- Theme
	"https://github.com/rebelot/kanagawa.nvim",
	"https://github.com/jmbuhr/otter.nvim",
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

-- Keymaps
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic quickfix" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus left" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus right" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus down" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus up" })
vim.keymap.set("n", "<leader>u", vim.pack.update, { desc = "Update plugins" })

-- Autocmds
vim.api.nvim_create_autocmd("TextYankPost", {
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	callback = function()
		if vim.fn.mode() ~= "c" then
			vim.cmd("checktime")
		end
	end,
})

-- Theme
require("kanagawa").setup({
	transparent = true,
	background = { dark = "dragon", light = "lotus" },
})
vim.cmd.colorscheme("kanagawa")

local function apply_hl_overrides()
	vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "LineNr", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "CursorLineNr", { bg = "NONE" })
	-- transparent = true in kanagawa lets the terminal bg show through;
	-- CursorLine needs a manual tint to remain visible over any background
	if vim.o.background == "dark" then
		vim.api.nvim_set_hl(0, "CursorLine", { bg = "#1f1f28", blend = 60 })
	else
		vim.api.nvim_set_hl(0, "CursorLine", { bg = "#e7e3d4", blend = 60 })
	end
	for _, hl in ipairs({
		"GitSignsAdd", "GitSignsChange", "GitSignsDelete",
		"GitSignsTopdelete", "GitSignsChangedelete", "GitSignsUntracked",
	}) do
		vim.api.nvim_set_hl(0, hl, { bg = "NONE" })
	end
	local fg, blue = "#181616", "#7fb4ca"
	vim.api.nvim_set_hl(0, "MiniStatuslineModeNormal", { bg = blue, fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineModeInsert", { bg = "#98bb6c", fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineModeVisual", { bg = "#957fb8", fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineModeReplace", { bg = "#c4746e", fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineModeCommand", { bg = "#c4b28a", fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineModeOther", { bg = blue, fg = fg, bold = true })
	vim.api.nvim_set_hl(0, "MiniStatuslineFileinfo", { bg = blue, fg = fg })
end

apply_hl_overrides()
vim.api.nvim_create_autocmd("ColorScheme", { callback = apply_hl_overrides })

-- UI
require("vim._core.ui2").enable({})
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
	p = { path = "~/Developer/study/physics", desc = "physics" },
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

require("render-markdown").setup({
	file_types = { "markdown" },
})

require("flash").setup()
vim.keymap.set({ "n", "x", "o" }, "s", function()
	require("flash").jump()
end, { desc = "Flash jump" })
vim.keymap.set({ "n", "x", "o" }, "S", function()
	require("flash").treesitter()
end, { desc = "Flash treesitter" })
vim.keymap.set("o", "r", function()
	require("flash").remote()
end, { desc = "Flash remote" })

local statusline = require("mini.statusline")
statusline.setup({
	use_icons = true,
	content = {
		active = function()
			local mode, mode_hl = statusline.section_mode({ trunc_width = 120 })
			local git = statusline.section_git({ trunc_width = 40 })
			local diff = statusline.section_diff({ trunc_width = 75 })
			local diagnostics = statusline.section_diagnostics({ trunc_width = 75 })
			local filename = statusline.section_filename({ trunc_width = 140 })
			local fileinfo = statusline.section_fileinfo({ trunc_width = 120 })
			local location = statusline.section_location({ trunc_width = 75 })
			return statusline.combine_groups({
				{ hl = mode_hl, strings = { mode:sub(1, 1) } },
				{ hl = "MiniStatuslineDevinfo", strings = { git, diff, diagnostics } },
				"%<",
				{ hl = "MiniStatuslineFilename", strings = { filename } },
				"%=",
				{ hl = "MiniStatuslineFileinfo", strings = { fileinfo } },
				{ hl = mode_hl, strings = { location } },
			})
		end,
	},
})

require("fidget").setup({})

-- Navigation
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
vim.keymap.set("n", "<leader>sD", fzf.git_status, { desc = "Search diffs" })
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

-- Diagnostics
vim.diagnostic.config({
	severity_sort = true,
	float = { border = "rounded", source = "if_many" },
	underline = { severity = vim.diagnostic.severity.ERROR },
	virtual_text = { source = "if_many", spacing = 2 },
})

-- Completion
require("supermaven-nvim").setup({})

-- LSP
require("lazydev").setup({
	library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
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
		if not client then return end

		if client:supports_method(vim.lsp.protocol.Methods.textDocument_completion) then
			vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
		end

		if client:supports_method(vim.lsp.protocol.Methods.textDocument_documentColor) then
			vim.lsp.document_color.enable(true, { bufnr = event.buf })
		end

		if client:supports_method(vim.lsp.protocol.Methods.textDocument_foldingRange) then
			vim.wo.foldmethod = "expr"
			vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"
			vim.wo.foldlevel = 99
		end

		if client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
			map("<leader>ch", function()
				vim.lsp.inlay_hint.enable(
					not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }),
					{ bufnr = event.buf }
				)
			end, "Toggle inlay hints")
		end

		if client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
			local hl_group = vim.api.nvim_create_augroup("lsp-highlight-" .. event.buf, { clear = true })
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = hl_group,
				callback = vim.lsp.buf.document_highlight,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = hl_group,
				callback = vim.lsp.buf.clear_references,
			})
			vim.api.nvim_create_autocmd("LspDetach", {
				buffer = event.buf,
				group = vim.api.nvim_create_augroup("lsp-attach", { clear = false }),
				once = true,
				callback = function()
					vim.lsp.buf.clear_references()
					pcall(vim.api.nvim_del_augroup_by_name, "lsp-highlight-" .. event.buf)
				end,
			})
		end
	end,
})

vim.lsp.config("lua_ls", { settings = { Lua = { completion = { callSnippet = "Replace" } } } })
vim.lsp.enable("eslint")
vim.lsp.enable("sourcekit") -- Swift; not mason-managed, uses system Xcode toolchain

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
		"taplo",
	},
})
require("mason-lspconfig").setup({ automatic_enable = true })

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
vim.api.nvim_create_autocmd("FileType", {
	pattern = "toml",
	group = vim.api.nvim_create_augroup("mise-otter", { clear = true }),
	callback = function()
		pcall(require("otter").activate)
	end,
})

-- Matches: *mise*.toml filenames, OR config.toml inside a mise//.mise directory.
vim.treesitter.query.add_predicate("is-mise?", function(_, _, bufnr, _)
	local filepath = vim.api.nvim_buf_get_name(tonumber(bufnr) or 0)
	local filename = vim.fn.fnamemodify(filepath, ":t")
	return string.match(filename, ".*mise.*%.toml$") ~= nil
		or string.match(filepath, "[/\\]%.?mise[/\\]") ~= nil
end, { force = true, all = false })


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
		"toml",
		"kdl",
		"tsx",
		"typescript",
		"vim",
		"vimdoc",
	},
	auto_install = true,
	highlight = { enable = true },
	indent = { enable = true },
})
