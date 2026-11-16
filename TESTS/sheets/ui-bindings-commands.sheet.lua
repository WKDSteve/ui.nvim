-- The :UI commands of the bindings checklist of the nvim config that answer with a message or switch a state
-- (BINDINGS-RUNTIME-CHECKLIST.md, section ":UI", ":Theme" and ":UI kit-presets"): each is typed on the command line
-- with the setup of the nvim config (TESTS/sheets/_bindings.lua), and the sheet reads the message it gave and the
-- colorscheme it left. The floats (:UI picker, keys, color, notify history, winpick, zen, screenkey, :KitPreview)
-- and <leader>bq are in ui-bindings-floats.sheet.lua.

local steps = {
  {
    lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_bindings.lua")]],
    note = "ui.setup as in the nvim config, vim.notify a recorder",
  },
}

local function add(step)
  steps[#steps + 1] = step
end

---Type `:cmd` and check what it said.
local function cmd(line, expect, note)
  add({ keys = ":" .. line .. "<CR>", note = ":" .. line .. ": " .. note })
  add({ expect = expect, note = ":" .. line .. " " .. note })
end

cmd(
  "UI status",
  [[_G.text():find("UI Status", 1, true) and _G.text():find("Theme:        tokyonight-storm", 1, true)
    and _G.text():find("Variant:      personal", 1, true) and _G.text():find("Transparency: off", 1, true)
    and _G.text():find("Toggle:       default, tok...", 1, true) and _G.said("Tabline style:", true)]],
  "shows theme, transparency, variant, tabline style and the toggle pair"
)

cmd(
  "UI themes",
  [[_G.text():find("Available themes %(%d+%):") and _G.text():find("\n  tokyonight\n", 1, true)
    and _G.text():find("\n  default", 1, true) and _G.said("✓ tokyonight-storm", true)]],
  "lists every colorscheme, the active one marked"
)

cmd(
  "UI theme",
  [[_G.said("Aktuelles Theme: tokyonight-storm", true)]],
  "shows the current colorscheme"
)
cmd(
  "UI theme tokyonight",
  [[vim.g.colors_name == "tokyonight" and _G.said("Theme changed to: tokyonight", true)]],
  "switches to it"
)
cmd(
  "UI theme no-such-theme",
  [[vim.g.colors_name == "tokyonight" and _G.said("Theme 'no-such-theme' not found", true)]],
  "refuses an unknown one and keeps the current"
)
cmd("Theme", [[_G.said("Aktuelles Theme: tokyonight", true)]], "is the shortcut of :UI theme")
cmd(
  "Theme tokyonight-storm",
  [[vim.g.colors_name == "tokyonight-storm" and _G.said("Theme changed to: tokyonight-storm", true)]],
  "switches like :UI theme"
)

-- The toggle pair of ui.config is { "default", "tokyonight" }; the config starts on tokyonight-storm, which is not
-- in it, so the first toggle goes to the first of the pair.
cmd(
  "UI toggle",
  [[vim.g.colors_name == "default" and _G.said("Theme changed to: default", true)]],
  "goes to the first theme of the pair"
)
cmd(
  "UI toggle",
  [[vim.g.colors_name == "tokyonight" and _G.said("Theme changed to: tokyonight", true)]],
  "then to the other one"
)
cmd(
  "UI toggle",
  [[vim.g.colors_name == "default" and _G.said("Theme changed to: default", true)]],
  "and back"
)

cmd(
  "UI tabline-styles",
  [[_G.text():find("Verfügbare Tabline%-Styles %(%d+%):")
    and _G.said("✓ " .. (require("ui.tabline.render").current().style or "rounded"), true)]],
  "lists the tabline styles, the active one marked"
)

cmd(
  "UI variants",
  [[_G.text():find("Available statusline variants (5):", 1, true) and _G.text():find("  default", 1, true)
    and _G.said("✓ personal", true)]],
  "lists the four shipped variants and the config's own, which is active"
)

cmd(
  "UI modules",
  [[_G.text():find('Built into the "default" theme', 1, true) and _G.text():find("Standalone modules", 1, true)
    and _G.said("docs/modules.md", true)]],
  "lists the statusline segments, built-in and standalone"
)

cmd(
  "UI progress",
  [[_G.said("No plugin operation is currently running.", true)]],
  "says that nothing runs"
)
add({
  lua = [[_G.op = require("lib.nvim.progress").create({ title = "[sheet]", style = "statusline", delay_ms = 0 })
    _G.op:update({ text = "indexing", current = 3, total = 10 })]],
  note = "an operation in progress, as a plugin starts one",
})
add({
  wait = [[#require("lib.nvim.progress.styles.statusline").active() == 1]],
  note = "it is in the registry",
})
cmd(
  "UI progress",
  [[_G.text():find("1 operation(s) in progress:", 1, true) and _G.said("indexing", true)]],
  "lists the running operation"
)
add({ lua = [[_G.op:finish()]] })

cmd(
  "UI kit-presets",
  [[_G.text():find("Available kit presets %(%d+%):") and _G.said("* " .. require("ui.kit.theme").default(), true)]],
  "lists the popup/toast presets, the active one marked"
)

add({ expect = [[_G.text() == ""]], note = "no message is left that no step asked for" })

return {
  id = "ui.bindings-commands",
  title = "The :UI commands of the nvim config answer with the state they name and switch the colorscheme",
  task = "ui.nvim/testblatt-bindings-checkliste",
  feature = "ui.theme",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  steps = steps,
  manual = {
    "In the real config: :UI themes lists the installed colorschemes (tokyonight and its styles among them) and :UI toggle switches between the two of `theme_toggle` with their real colours",
  },
}
