-- Feature sheet: the clickable git segment of the statusline (`git_clickable`) in a real repository.
-- A left click in a repository without commits says so (it asks git whether this is a repository at all), a
-- left click with two branches offers them as buttons and switches to the one picked (`git checkout`), a right
-- click opens the segment's menu whose "Details" shows `git status --short --branch`. git runs for real in a
-- throwaway repository (TESTS/sheets/fixtures/git_repo.lua); gitsigns, which gives the segment its text, is not
-- a dependency of the sheets: its two buffer variables stand in for it.
return {
  id = "statusline.git-branch",
  feature = "ui.statusline-git",
  title = "The git segment: a click switches the branch, the right-click menu shows the status",
  engine = "rpc",
  steps = {
    {
      lua = [[
      vim.opt.shortmess:append("I")
      vim.o.swapfile = false
      vim.o.laststatus = 2
      _G.msgs = {}
      vim.notify = function(msg) _G.msgs[#_G.msgs + 1] = tostring(msg) end
      _G.said = function(text)
        for _, m in ipairs(_G.msgs) do
          if m:find(text, 1, true) then return true end
        end
        return false
      end
      dofile(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/git_repo.lua")
      vim.cmd.cd(_G.repo.dir)
      vim.cmd.edit(_G.repo.dir .. "/file.txt")]],
      note = "a file in a fresh repository without commits, its directory the cwd",
    },
    {
      lua = [[
      require("ui").setup({ vim_ui = true })
      require("ui.statusline.render").enable({
        order = { "git_clickable" },
        modules = { git_clickable = require("ui.statusline.modules.git_clickable") },
      })
      vim.b.gitsigns_head = "main"
      vim.b.gitsigns_status_dict = { head = "main" }
      vim.cmd.redrawstatus()]],
      note = "the statusline with the git segment; gitsigns' buffer state stands in for gitsigns",
    },
    { input = "<LeftMouse><2,22>", note = "left click on the branch in the statusline" },
    {
      wait = "_G.said('repository has no commits yet')",
      timeout = 5000,
      note = "no branch to offer: the message names the empty repository",
    },
    {
      lua = '_G.repo.commit("first"); _G.repo.branch("feature")',
      note = "one commit, a second branch",
    },
    { input = "<LeftMouse><2,22>", note = "left click again" },
    {
      wait = "vim.api.nvim_win_get_config(0).relative ~= ''",
      timeout = 5000,
      note = "the two branches as buttons",
    },
    { keys = "f", note = "the hotkey of the button feature" },
    {
      wait = "_G.said('Switched to branch feature')",
      timeout = 5000,
      note = "the checkout ran",
    },
    {
      expect = "vim.trim(_G.repo.git({ 'symbolic-ref', '--short', 'HEAD' })) == 'feature'",
      note = "the repository is on feature",
    },
    { input = "<RightMouse><2,22>", note = "right click on the branch" },
    {
      wait = "vim.api.nvim_win_get_config(0).relative ~= ''",
      timeout = 5000,
      note = "the segment's menu: switch, copy, details",
    },
    { keys = "jj<CR>", note = "the third row, Details" },
    {
      wait = "_G.said('## feature')",
      timeout = 5000,
      note = "git status names the branch",
    },
  },
  manual = {
    "With gitsigns.nvim in the real config: the segment shows the branch by itself, a click switches",
  },
}
