-- TESTS/sheets/features.lua -- the functionalities of ui.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names
-- an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/BINDINGS.md (commands and keymaps), docs/modules.md and docs/configuration.md.
return {
  {
    id = "ui.option-float",
    title = "A bare :UI opens the option float with the switches of the plugin; q closes it",
    surface = { "command:UI" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.statusline",
    title = "The statusline in one of four presets, switched at runtime with :UI variant; :UI modules lists its segments",
    surface = { "command:UI variant", "command:UI modules" },
    docs = "docs/modules.md",
  },
  {
    id = "ui.statusline-mouse",
    title = "Statusline segments are clickable, with a hover tooltip and a menu to manage the module",
    docs = "docs/modules.md",
  },
  {
    id = "ui.tabline",
    title = "The tabline shows buffers and tabs as chips with pinning, reopening and mouse; :UI tabline-style",
    surface = { "command:UI tabline-style" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.theme",
    title = ":UI theme, themes, picker and toggle switch the colorscheme, the picker previews live",
    surface = { "command:UI theme", "command:UI picker", "command:UI toggle" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.transparency",
    title = ":UI transparency switches the background transparency",
    surface = { "command:UI transparency" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.slots",
    title = "Numbered action slots in a bar of chips: :UI slots runs, adds, yanks and clears them",
    surface = { "command:UI slots" },
    docs = "lua/ui/slots/README.md",
  },
  {
    id = "ui.dialogs",
    title = "Confirm dialogs mark the hotkey letter or digit of each button",
    docs = "docs/modules.md",
  },
  {
    id = "ui.kit-presets",
    title = ":UI kit-preset switches the border and colours of every popup and toast; :UI kit-playground shows them",
    surface = { "command:UI kit-preset", "command:UI kit-playground" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.notify",
    title = ":UI notify renders vim.notify as toasts, with a history viewer",
    surface = { "command:UI notify" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.keys",
    title = ":UI keys shows the mappings under a prefix as a menu",
    surface = { "command:UI keys" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.sticky",
    title = ":UI sticky pins the enclosing context (Markdown headings, code scopes) at the top of the window",
    surface = { "command:UI sticky" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.winpick",
    title = ":UI winpick jumps to a window by its letter",
    surface = { "command:UI winpick" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.zen",
    title = ":UI zen shows the buffer alone in a centred float over a dimmed backdrop",
    surface = { "command:UI zen" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.colorpicker",
    title = ":UI color opens an interactive colour picker",
    surface = { "command:UI color" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.screenkey",
    title = ":UI screenkey shows the typed keys in the editor, for recordings",
    surface = { "command:UI screenkey" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.progress",
    title = ":UI progress lists the running progress of plugins in a popup",
    surface = { "command:UI progress" },
    docs = "docs/BINDINGS.md",
  },
  {
    id = "ui.context-menu",
    title = "Opt-in: a right-click menu of the editor",
    docs = "docs/BINDINGS.md",
  },
}
