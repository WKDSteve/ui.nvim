-- The menu warm-up on the real startup path: setup() starts the idle preload, which ends in the hidden open/close
-- of the context menu (`ui.menu.warm`). The spec calls warm() directly with `state()` stubbed; this sheet lets the
-- chain run by itself in an idle editor and checks that the user's buffer and window saw no Leave/Enter event
-- (multicursor in the nvim config dropped its marks on that BufLeave), while the warm-up did open its window.
return {
  id = "menu.warm-quiet",
  feature = "ui.context-menu",
  title = "The menu warm-up after startup fires no Leave/Enter events on the user's buffer",
  task = "ui.nvim/menu-warm-leave-enter-events-auf-dem-nutzer-buffer-vermeiden",
  engine = "rpc",
  steps = {
    { lua = 'vim.opt.shortmess:append("I"); vim.o.swapfile = false' },
    {
      lua = [[
      vim.cmd.edit("user.txt")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "the user's buffer" })
      _G.ubuf, _G.uwin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
      _G.user_hits, _G.new_wins, _G.warmed = {}, 0, nil
      vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "BufEnter", "WinEnter" }, {
        callback = function(a)
          if a.buf == _G.ubuf or vim.api.nvim_get_current_win() == _G.uwin then
            table.insert(_G.user_hits, a.event)
          end
        end,
      })
      vim.api.nvim_create_autocmd("WinNew", { callback = function() _G.new_wins = _G.new_wins + 1 end })
      local menu = require("ui.menu")
      local real = menu.warm
      menu.warm = function()
        local ok = real()
        _G.warmed = ok
        return ok
      end]],
      note = "a file in the window, counters for its events, warm() watched",
    },
    {
      lua = [[require("ui.menu").setup({ mouse = false, key = false, renderer = "kit", prewarm = true })]],
      note = "the menu with its idle preload, as at startup",
    },
    {
      wait = "_G.warmed ~= nil",
      timeout = 10000,
      note = "the preload ran and ended in the warm-up",
    },
    { expect = "_G.warmed == true", note = "the warm-up opened and closed the menu" },
    {
      expect = "_G.new_wins >= 1",
      note = "its window was made (what lazy plugins load on still happens)",
    },
    { expect = "#_G.user_hits == 0", note = "no Leave/Enter event on the user's buffer or window" },
    {
      expect = "vim.wo[_G.uwin].eventignorewin == ''",
      note = "nothing left behind on the user's window",
    },
    { expect = "vim.api.nvim_get_current_win() == _G.uwin", note = "the focus is where it was" },
  },
}
