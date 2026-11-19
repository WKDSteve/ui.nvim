-- Feature sheet: the idle_git_log segment of the statusline in a real repository. The user edits a file of a
-- repository with three commits and stops typing: once the editor is idle (`updatetime`, `CursorHold`) the
-- segment reads the last commits with `git log` and shows them. git runs for real in a throwaway repository
-- (TESTS/sheets/fixtures/git_repo.lua). That a key hides them again is TESTS/idle_git_log_spec.lua's.
return {
  id = "statusline.idle-git-log",
  feature = "ui.statusline-idle-git-log",
  title = "The idle git log: the last commits show in the statusline while the editor is idle",
  engine = "rpc",
  steps = {
    {
      lua = [[
      vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      vim.o.laststatus = 2
      dofile(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/git_repo.lua")
      _G.repo.commit("Add the parser")
      _G.repo.commit("Add tests")
      _G.repo.commit("Fix the parser")
      vim.cmd.edit(_G.repo.dir .. "/file.txt")
      _G.stl = function()
        return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win() }).str
      end]],
      note = "a file of a repository with three commits",
    },
    {
      lua = [[
      require("ui.statusline.render").enable({
        order = { "idle_git_log" },
        modules = {
          idle_git_log = function()
            return require("ui.statusline.modules.idle_git_log")({ max_count = 2 })
          end,
        },
      })
      vim.cmd.redrawstatus()]],
      note = "the statusline with the idle git log, two commits, as docs/modules.md wires it",
    },
    { keys = "j", note = "a key: the editor is active" },
    { expect = "not _G.stl():find('Fix the parser', 1, true)", note = "nothing while active" },
    { lua = "vim.o.updatetime = 200", note = "a short idle time" },
    {
      wait = "_G.stl():find('Fix the parser', 1, true) ~= nil",
      timeout = 8000,
      note = "idle: the newest commit shows",
    },
    { expect = "_G.stl():find('Add tests', 1, true) ~= nil", note = "and the one before" },
    {
      expect = "not _G.stl():find('Add the parser', 1, true)",
      note = "max_count = 2: the third is not shown",
    },
  },
  manual = {
    "In the real config: stop typing in a file of a repository, the commits come; a key hides them",
  },
}
