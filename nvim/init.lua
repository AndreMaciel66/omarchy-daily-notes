-- Neovim dedicado às notas diárias (carregado com NVIM_APPNAME=nvim-daily).
-- Config crua de propósito: só o básico para escrever markdown com conforto.
-- Vamos evoluir isso depois (plugins, tema, atalhos).

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.opt

-- Aparência
o.termguicolors = true
o.number = false
o.relativenumber = false
o.signcolumn = "no"
o.cursorline = true
o.showmode = false
o.laststatus = 2
o.cmdheight = 1
o.conceallevel = 2

-- Texto corrido
o.wrap = true
o.linebreak = true
o.breakindent = true
o.textwidth = 0
o.spelllang = { "pt_br", "en" }

-- Edição
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.clipboard = "unnamedplus"
o.undofile = true
o.swapfile = false
o.autowrite = true
o.autowriteall = true
o.updatetime = 300
o.mouse = "a"
o.ignorecase = true
o.smartcase = true

-- Salva automaticamente ao perder foco ou trocar de buffer.
vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave", "InsertLeave" }, {
  pattern = "*.md",
  callback = function()
    if vim.bo.modified and vim.bo.buftype == "" and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! write")
    end
  end,
})

-- Markdown por padrão para tudo que abrir por aqui.
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.md",
  callback = function()
    vim.bo.filetype = "markdown"
  end,
})

-- Atalhos
local map = vim.keymap.set
map("n", "<leader>q", "<cmd>wqa<cr>", { desc = "Salvar e fechar" })
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Salvar" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Limpar busca" })
map("n", "<leader>d", function()
  vim.api.nvim_put({ os.date("## %H:%M") }, "l", true, true)
end, { desc = "Inserir carimbo de hora" })
