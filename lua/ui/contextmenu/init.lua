---@module 'ui.contextmenu'
--- Re-export: the context menu lives in lib.nvim (`lib.nvim.contextmenu`), one module and one state for both names
--- (like `ui.kit.*`). `ui.setup({ menu = false })` reaches `set_enabled` of that one module.
return require("lib.nvim.contextmenu")
