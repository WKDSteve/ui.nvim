-- TESTS/sheets/_bindings.lua -- the setup of the binding sheets (ui-bindings-*.sheet.lua). Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); the first step of such a sheet runs it with `dofile`, the child's cwd is
-- the project root. The directory is in the spec's @cache-inputs.
--
-- Covers the ui.nvim items of the bindings runtime checklist of the nvim config
-- (docs/ROADMAP/Final_Checks/BINDINGS-RUNTIME-CHECKLIST.md): every command and key is typed as a person types it,
-- and the sheet reads what it did -- the message it gave, the float it opened, the colorscheme it switched to.
--
-- The configuration mirrors the one of the nvim config (lua/config/ui_statusline/init.lua): the same `ui.setup`
-- (usrcmds, every default key, the sticky context, vim.ui through the kit), the variant "personal" registered and
-- assembled, the tabufline state, the statusline and the tabline enabled. What stays out: the slots, the right-click
-- menu and the task counter (sheets of their own) and snacks as the fallback of a long vim.ui.select list (the
-- kit's chooser takes it, as the config does without snacks). The variant is the upstream template the config's
-- own is copied from (docs/examples/personal-statusline-example.lua). The colorschemes are stand-ins of the
-- config's tokyonight (a fixture folder on the runtimepath): `tokyonight-storm` is what the config loads at
-- startup, `default` and `tokyonight` are the `theme_toggle` pair of ui.config.
--
-- Messages: vim.notify is a recorder (`_G.msgs`), so a long message raises no hit-enter prompt that would hold
-- the next key; `_G.said(pattern)` reads them.

-- luacheck: globals vim

vim.opt.shortmess:append("I")
vim.o.swapfile = false
vim.g.mapleader = " "

---@type { msg: string, level: integer? }[]
_G.msgs = {}
_G.recorder = function(msg, level)
  _G.msgs[#_G.msgs + 1] = { msg = tostring(msg), level = level }
end
vim.notify = _G.recorder

-- The colorschemes of the fixture: each clears, sets its own Normal background and its name.
local tmp = vim.fs.normalize(vim.fn.tempname())
_G.fixture = tmp
vim.fn.mkdir(tmp .. "/colors", "p")
for name, bg in pairs({ ["tokyonight"] = "#1a1b26", ["tokyonight-storm"] = "#24283b" }) do
  vim.fn.writefile({
    "vim.cmd('highlight clear')",
    ("vim.g.colors_name = %q"):format(name),
    ("vim.api.nvim_set_hl(0, 'Normal', { fg = '#c0caf5', bg = %q })"):format(bg),
  }, tmp .. "/colors/" .. name .. ".lua")
end
vim.opt.runtimepath:append(tmp)
vim.cmd.colorscheme("tokyonight-storm")

require("ui").setup({
  usrcmds = true,
  keymaps = true,
  vim_ui = { buttons_max = 4, chooser_max = 12 },
  sticky = {
    max_lines = { default = 3, markdown = 6 },
    headings = { max_level = 6 },
    persist = false, -- the config keeps it; a sheet does not write into stdpath("state")
    position = { anchor = "top-right" },
    style = "chips",
    chips = { layout = "stack" },
  },
})
require("ui.config.variants").register(
  "personal",
  dofile(vim.fn.getcwd() .. "/docs/examples/personal-statusline-example.lua")
)
local assembled = require("ui.config").setup({ variant = "personal" })
require("ui.bindings.keymaps.tabufline.state").setup()
require("ui.statusline.render").enable(assembled.ui.statusline)
require("ui.tabline.render").enable(assembled.ui.tabline)

local function fail(fmt, ...)
  error(fmt:format(...), 0)
end

---Whether a recorded message matches `pattern` (a Lua pattern, `plain` for a plain find). The messages are cleared
---after it, so the next step reads only what its own command said.
---@param pattern string
---@param plain? boolean
---@return boolean
function _G.said(pattern, plain)
  for _, m in ipairs(_G.msgs) do
    if m.msg:find(pattern, 1, plain) then
      _G.msgs = {}
      return true
    end
  end
  local got = {}
  for _, m in ipairs(_G.msgs) do
    got[#got + 1] = m.msg
  end
  fail("no message %q among %s", pattern, vim.inspect(got))
end

---The text of every message recorded since the last `said`, joined.
---@return string
function _G.text()
  local got = {}
  for _, m in ipairs(_G.msgs) do
    got[#got + 1] = m.msg
  end
  return table.concat(got, "\n")
end

---The floating windows, focusable ones only unless `all`.
---@param all? boolean
---@return integer[]
function _G.floats(all)
  return vim.tbl_filter(function(w)
    local c = vim.api.nvim_win_get_config(w)
    return c.relative ~= "" and (all or c.focusable)
  end, vim.api.nvim_list_wins())
end

---The lines of the focused float, joined, or "" when the focus is not in a float.
---@return string
function _G.float_text()
  if vim.api.nvim_win_get_config(0).relative == "" then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

return {}
