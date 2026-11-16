-- The items of the bindings checklist of the nvim config that open something (BINDINGS-RUNTIME-CHECKLIST.md,
-- sections "ui.nvim", ":UI" and ":KitPreview"): <leader>bq, :UI picker, keys, color, screenkey, zen, notify, winpick
-- and :KitPreview, with the setup of the nvim config (TESTS/sheets/_bindings.lua). Each is typed as a person types
-- it, and the sheet reads what opened, what it shows and what is left once it is closed. How it looks is the
-- judge's; the commands that only answer with a message are in ui-bindings-commands.sheet.lua.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "ui.setup as in the nvim config, vim.notify a recorder",
  },
}

local function add(step)
  steps[#steps + 1] = step
end

local NO_FLOAT = "#_G.floats() == 0"

-- <leader>bq: every listed buffer of the tab flashes, then all of them close.
add({
  lua = [[
  local utils = require("ui.tabline.utils")
  local flash = utils.flash
  _G.flashed = {}
  utils.flash = function(b) _G.flashed[#_G.flashed + 1] = b; return flash(b) end
  vim.cmd.edit(vim.fn.fnameescape(_G.fixture .. "/a.txt"))
  _G.a = vim.api.nvim_get_current_buf()
  vim.cmd.edit(vim.fn.fnameescape(_G.fixture .. "/b.txt"))
  _G.b = vim.api.nvim_get_current_buf()]],
  note = "two clean buffers in the tab, the flash recorded",
})
add({
  wait = "vim.tbl_contains(vim.t.bufs or {}, _G.a) and vim.tbl_contains(vim.t.bufs or {}, _G.b)",
  note = "both are in the tab's list",
})
add({ keys = " bq", note = "<leader>bq: close every listed buffer of the tab" })
add({
  expect = "vim.tbl_contains(_G.flashed, _G.a) and vim.tbl_contains(_G.flashed, _G.b)",
  note = "both flashed first",
})
add({
  wait = [[not (vim.api.nvim_buf_is_valid(_G.a) and vim.bo[_G.a].buflisted)
    and not (vim.api.nvim_buf_is_valid(_G.b) and vim.bo[_G.b].buflisted)]],
  note = "then both are closed",
})

-- :UI picker: the theme under the cursor applies live, <Esc> restores, <CR> keeps.
add({ keys = ":UI picker<CR>", note = ":UI picker: the visual theme picker" })
add({
  wait = [[_G.float_text():find("tokyonight-storm", 1, true) ~= nil]],
  note = "a float lists the colorschemes",
})
add({
  expect = [[vim.api.nvim_get_current_line():find("tokyonight-storm", 1, true) ~= nil]],
  note = "the cursor is on the active one",
})
add({ keys = "k", note = "one up" })
add({ wait = [[vim.g.colors_name == "tokyonight"]], note = "the one under the cursor is previewed" })
add({ keys = "<Esc>", note = "cancel" })
add({
  wait = [[vim.g.colors_name == "tokyonight-storm" and ]] .. NO_FLOAT,
  note = "the float is gone, the theme from before is back",
})
add({ keys = ":UI picker<CR>" })
add({ wait = [[_G.float_text() ~= ""]] })
add({ keys = "k<CR>", note = "one up and confirm" })
add({
  wait = [[vim.g.colors_name == "tokyonight" and ]] .. NO_FLOAT,
  note = "the confirmed theme stays",
})

-- :UI keys: the mappings under a prefix, the default prefix <leader>.
add({ keys = ":UI keys<CR>", note = ":UI keys: the mappings under <leader>" })
add({ wait = [[_G.float_text() ~= ""]], note = "a menu opens" })
add({
  expect = [[_G.float_text():find("b ▸", 1, true) ~= nil and _G.float_text():find("u ▸", 1, true) ~= nil]],
  note = "it has the <leader>b and <leader>u groups of the default keys",
})
add({ keys = "<Esc>" })
add({ wait = NO_FLOAT, note = "<Esc> closes it" })
add({
  keys = ":UI keys <C-r>=nr2char(60) .. 'leader>b'<CR><CR>",
  note = ":UI keys <leader>b: one prefix",
})
add({ wait = [[_G.float_text() ~= ""]] })
add({
  expect = [[_G.float_text():find("close every listed buffer", 1, true) ~= nil
    and _G.float_text():find("pin/unpin", 1, true) ~= nil]],
  note = "it lists the buffer keys by their description",
})
add({ keys = "<Esc>" })
add({ wait = NO_FLOAT })
add({
  keys = ":UI keys <C-r>=nr2char(60) .. 'leader>Q'<CR><CR>",
  note = "a prefix nothing is mapped under",
})
add({
  expect = [[]] .. NO_FLOAT .. [[ and _G.said("no mappings under <leader>Q", true)]],
  note = "no menu, a message instead",
})

-- :UI color: the colour picker, on a colour given or the default.
add({ keys = ":UI color #3366cc<CR>", note = ":UI color #3366cc: the colour picker on that colour" })
add({ wait = [[require("ui.colorpicker").current() ~= nil]], note = "the picker is open" })
add({
  expect = [[require("ui.colorpicker").current():lower() == "#3366cc"]],
  note = "on the colour given",
})
add({ keys = "q" })
add({ wait = [[require("ui.colorpicker").current() == nil and ]] .. NO_FLOAT, note = "q closes it" })
add({ keys = ":UI color<CR>", note = ":UI color: without a colour" })
add({ wait = [[require("ui.colorpicker").current() ~= nil]], note = "it opens on its default" })
add({ keys = "q" })
add({ wait = [[require("ui.colorpicker").current() == nil]] })
add({ keys = ":UI color nope<CR>", note = "not a colour" })
add({
  expect = [[require("ui.colorpicker").current() == nil and _G.said("not a colour: nope", true)]],
  note = "is refused with a message",
})

-- :UI screenkey: the keystroke HUD.
add({ keys = ":UI screenkey<CR>", note = ":UI screenkey: on" })
add({
  expect = [[require("ui.screenkey").is_enabled() and _G.said("Screenkey enabled", true)]],
  note = "it is on",
})
add({ keys = "jk", note = "two keys" })
add({
  wait = [[(function()
    local s = require("ui.screenkey").surface()
    if not (s and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr)) then return false end
    local t = table.concat(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false), " ")
    return t:find("j", 1, true) ~= nil and t:find("k", 1, true) ~= nil
  end)()]],
  note = "the HUD shows them",
})
add({ keys = ":UI screenkey<CR>", note = ":UI screenkey: off again" })
add({
  expect = [[not require("ui.screenkey").is_enabled() and require("ui.screenkey").surface() == nil
    and _G.said("Screenkey disabled", true)]],
  note = "it is off and the HUD is gone",
})

-- :UI zen: the distraction-free box.
add({ lua = [[_G.laststatus = vim.o.laststatus]] })
add({ keys = ":UI zen<CR>", note = ":UI zen: on" })
add({
  expect = [[require("ui.zen").is_open() and vim.api.nvim_get_current_win() == require("ui.zen").win()
    and vim.o.laststatus == 0]],
  note = "the zen box has the focus, the statusline is hidden",
})
add({ keys = ":UI zen<CR>", note = ":UI zen: off" })
add({
  expect = [[not require("ui.zen").is_open() and vim.o.laststatus == _G.laststatus and _G.said("Zen off", true)]],
  note = "the box is gone, the statusline is back",
})

-- :UI notify: toasts with a history.
add({ keys = ":UI notify<CR>", note = ":UI notify: toasts on" })
add({
  expect = [[require("ui.notify").is_enabled() and vim.notify == require("ui.notify").handler]],
  note = "vim.notify is the toast handler",
})
add({
  expect = [[#require("ui.notify").history() == 1
    and require("ui.notify").history()[1].msg:find("Notify toasts enabled", 1, true) ~= nil]],
  note = "its own message is the first one of the history",
})
add({ keys = ":UI notify history<CR>", note = ":UI notify history" })
add({
  wait = [[_G.float_text():find("Notify toasts enabled", 1, true) ~= nil]],
  note = "the history opens",
})
add({ keys = "q" })
add({ wait = NO_FLOAT, note = "q closes it" })
add({ keys = ":UI notify clear<CR>", note = ":UI notify clear" })
add({
  expect = [[#require("ui.notify").history() == 1
    and require("ui.notify").history()[1].msg:find("Notification history cleared", 1, true) ~= nil]],
  note = "the history is empty but for the message saying so",
})
add({ keys = ":UI notify off<CR>", note = ":UI notify off" })
add({
  expect = [[not require("ui.notify").is_enabled() and vim.notify == _G.recorder
    and _G.said("Notify toasts disabled", true)]],
  note = "vim.notify is the one from before again",
})

-- :UI winpick: three windows, a letter jumps.
add({
  lua = [[vim.cmd("only | vsplit | split"); _G.origin = vim.api.nvim_get_current_win()]],
  note = "three windows",
})
add({
  input = ":UI winpick<CR>",
  note = ":UI winpick: the letters are shown, the pick waits for a key (queued keys reach its getchar)",
})
add({ input = "j", note = "the second letter" })
add({
  wait = [[require("ui.windowpicker").last_call().prompted and require("ui.windowpicker").last_call().picked ~= nil]],
  note = "it asked and a window was picked",
})
add({
  expect = [[vim.api.nvim_get_current_win() == require("ui.windowpicker").last_call().picked
    and vim.api.nvim_get_current_win() ~= _G.origin and #_G.floats(true) == 0]],
  note = "the focus is in the picked window, the hints are gone",
})
add({ lua = [[vim.cmd("only")]] })

-- :KitPreview: the live theme playground, a tab of its own.
add({ keys = ":KitPreview<CR>", note = ":KitPreview: the playground" })
add({
  wait = [[#vim.api.nvim_list_tabpages() == 2 and vim.bo.filetype == "lua"]],
  note = "a new tab, the config in the left window",
})
add({
  lua = [[_G.preview_text = function()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if b ~= vim.api.nvim_get_current_buf() then
        return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
      end
    end
    return ""
  end]],
})
add({
  wait = [[_G.preview_text():find("border=rounded", 1, true) ~= nil]],
  note = "the preview on the right shows the rounded border",
})
add({ keys = "<Tab>", note = "the next preset" })
add({
  wait = [[_G.preview_text():find("border=", 1, true) ~= nil and _G.preview_text():find("border=rounded", 1, true) == nil]],
  note = "the preview follows the config",
})
add({ keys = "q", note = "q closes the playground" })
add({ wait = [[#vim.api.nvim_list_tabpages() == 1]], note = "its tab is gone" })

add({ expect = [[_G.text() == ""]], note = "no message is left that no step asked for" })

return {
  id = "ui.bindings-floats",
  title = "<leader>bq, :UI picker, keys, color, screenkey, zen, notify, winpick and :KitPreview open what they name and close cleanly",
  task = "ui.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  steps = steps,
  judge = {
    "<leader>bq: the chips flash visibly before they close",
    "The theme picker, the keys menu, the colour picker, the notify history and the window letters read well",
  },
  manual = {
    "In the real config: :UI picker previews the installed colorschemes with their real colours while the cursor moves",
  },
}
