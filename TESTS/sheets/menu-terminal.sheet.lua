-- Feature sheet: "Open in terminal" of the editor's context menu. The user has a file of another directory open,
-- opens the menu with its key, goes down to the row and picks it: a terminal buffer runs 'shell' in the file's
-- directory (not the editor's cwd). The shell runs for real and is closed again at the end, so nothing is left.
return {
  id = "menu.open-terminal",
  feature = "ui.context-menu",
  title = "The context menu's Open in terminal starts the shell in the file's directory",
  engine = "rpc",
  steps = {
    {
      lua = [[
      vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      _G.dir = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(_G.dir, "p")
      vim.fn.writefile({ "a file elsewhere" }, _G.dir .. "/notes.txt")
      vim.cmd.edit(_G.dir .. "/notes.txt")
      _G.file_buf = vim.api.nvim_get_current_buf()]],
      note = "a file outside the cwd in the window",
    },
    {
      lua = [[require("ui.menu").setup({ mouse = false, key = "<F9>", renderer = "kit", prewarm = false })]],
      note = "the menu on a key, as a mouse-less user binds it",
    },
    { keys = "<F9>", note = "open the menu at the cursor" },
    {
      wait = "vim.api.nvim_win_get_config(0).relative ~= ''",
      timeout = 5000,
      note = "the menu is open",
    },
    {
      lua = [[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for _ = 1, #lines do
        if vim.api.nvim_get_current_line():find("Open in terminal", 1, true) then break end
        vim.api.nvim_feedkeys("j", "mx", false)
      end]],
      note = "j until the cursor is on Open in terminal (the rows above it depend on the buffer)",
    },
    {
      expect = "vim.api.nvim_get_current_line():find('Open in terminal', 1, true) ~= nil",
      note = "the cursor is on the entry",
    },
    { keys = "<CR>", note = "pick it" },
    {
      wait = "vim.bo.buftype == 'terminal'",
      timeout = 5000,
      note = "a terminal buffer in the window",
    },
    {
      expect = "vim.fn.jobwait({ vim.bo.channel }, 0)[1] == -1",
      note = "its shell runs",
    },
    {
      expect = "vim.api.nvim_buf_is_valid(_G.file_buf) and vim.api.nvim_get_current_buf() ~= _G.file_buf",
      note = "the file stays, the terminal is a buffer of its own",
    },
    {
      lua = "vim.fn.jobstop(vim.bo.channel); vim.cmd('bwipeout!')",
      note = "close the shell again",
    },
  },
  manual = {
    "In the real config: right click in a file, Open in terminal; pwd in the shell names the file's directory",
  },
}
