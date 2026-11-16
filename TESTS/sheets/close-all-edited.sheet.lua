-- Live check (task ALL/live-check-nachtrag-casedesk-nein-ja-data-vorschau-fokus-ui, point 3): `<leader>bq` with an unsaved
-- buffer asks once whether to discard; a buffer that is changed while the dialog is open was not covered by the question
-- and stays open after "yes", the one that was asked about closes.
return {
  id = "tabufline.close-all-edited",
  feature = "ui.tabline",
  title = "<leader>bq: a buffer edited while the discard question is open stays open",
  task = "ALL/live-check-nachtrag-casedesk-nein-ja-data-vorschau-fokus-ui",
  engine = "rpc",
  steps = {
    { lua = 'vim.opt.shortmess:append("I"); vim.o.swapfile = false; vim.g.mapleader = " "' },
    {
      lua = [[require("ui").setup({ keymaps = true })]],
      note = "the keymaps and the tab's buffer list",
    },
    {
      lua = [[
      vim.cmd.edit("asked.txt")
      _G.asked = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
      vim.cmd.edit("later.txt")
      _G.later = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "clean" })
      vim.bo.modified = false
      -- the tab's own list (BufEnter of the tabufline) must know both
      _G.listed = function(b) return vim.tbl_contains(vim.t.bufs or {}, b) end]],
      note = "asked.txt unsaved, later.txt clean",
    },
    { wait = "_G.listed(_G.asked) and _G.listed(_G.later)", note = "both are in the tab's list" },
    { keys = "<Space>bq", note = "close all" },
    {
      wait = [[#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" and vim.api.nvim_win_get_config(w).focusable end, vim.api.nvim_list_wins()) > 0]],
      note = "the discard question is open",
    },
    { settle = 300 },
    { screen = "question" },
    {
      lua = [[vim.api.nvim_buf_set_lines(_G.later, 0, -1, false, { "edited while asked" })]],
      note = "later.txt changes while the dialog is open",
    },
    { keys = "y", note = "yes, discard" },
    {
      wait = "not vim.api.nvim_buf_is_valid(_G.asked) or not vim.bo[_G.asked].buflisted",
      note = "the buffer the question was about is closed",
    },
    {
      expect = [[vim.api.nvim_buf_is_valid(_G.later) and vim.bo[_G.later].buflisted and vim.bo[_G.later].modified
        and vim.api.nvim_buf_get_lines(_G.later, 0, -1, false)[1] == "edited while asked"]],
      note = "the buffer edited meanwhile stays open with its change",
    },
  },
  judge = {
    "The question names one modified buffer and reads well",
  },
}
