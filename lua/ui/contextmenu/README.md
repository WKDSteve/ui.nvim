# `ui.contextmenu`

A re-export of [`lib.nvim.contextmenu`](https://github.com/WKDSteve/lib.nvim/tree/main/lua/lib/nvim/contextmenu):
one module and one state under both names, the way `ui.kit.*` re-exports `lib.nvim.ui.kit.*`. The item builders
(`entry`/`group`/`submenu`/`heading`), the renderer (`open`), the mouse trigger (`bind_buffer`), `setup`
(`renderer`, `native_popup`) and the opt-out `set_enabled`/`is_enabled` are documented in lib.nvim's README.

`ui.setup({ menu = false })` calls `set_enabled(false)`: the menu then never renders, the builders keep working.
