-- Feature sheet: LSP progress in the statusline (`lsp_msg`). Two language servers report at once; the end of one
-- leaves the other's running progress on the statusline, a burst of reports redraws it only a few times (throttled),
-- and the last state is still drawn. The servers are stood in for by `LspProgress` events, the way Neovim's own
-- `vim.lsp` fires them (client id, token, value); `_G.status()` reads the rendered statusline of the window.
return {
  id = "statusline.lsp-progress",
  feature = "ui.statusline",
  title = "LSP progress: one server's end keeps another's message, a burst of reports redraws a few times",
  engine = "rpc",
  sizes = { { rows = 24, cols = 140 } },
  steps = {
    {
      lua = [[
      vim.opt.shortmess:append("I")
      vim.o.laststatus = 2
      require("ui").setup({})
      local built = require("ui.statusline.themes.default").build("default")
      require("ui.statusline.render").enable({ order = { "lsp_msg" }, modules = built })
      _G.status = function()
        return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win() }).str
      end
      _G.progress = function(client, token, value)
        vim.api.nvim_exec_autocmds("LspProgress", {
          pattern = value.kind,
          data = { client_id = client, params = { token = token, value = value } },
        })
      end
      local primitives = require("ui.statusline.utils.primitives")
      local redraw = primitives._redraw
      _G.redraws = 0
      primitives._redraw = function()
        _G.redraws = _G.redraws + 1
        redraw()
      end]],
      note = "the statusline with only the LSP-progress segment, 140 columns (it stays empty below 120)",
    },
    {
      lua = [[
      _G.progress(1, "idx", { kind = "begin", title = "Indexing" })
      _G.progress(2, "bld", { kind = "begin", title = "Building" })]],
      note = "two servers begin: rust-analyzer indexes, a second one builds",
    },
    { wait = "_G.status():find('Building', 1, true)", note = "the newer message is shown" },
    { lua = '_G.progress(2, "bld", { kind = "end" })', note = "the build ends" },
    {
      wait = "_G.status():find('Indexing', 1, true)",
      note = "the other server's indexing is still shown, not cleared by the build's end",
    },
    {
      lua = [[
      _G.redraws = 0
      for i = 1, 300 do
        _G.progress(1, "idx", { kind = "report", percentage = math.floor(i / 3), message = i .. "/300" })
      end]],
      note = "300 reports in one go, as a busy server sends them",
    },
    {
      expect = "_G.redraws <= 3",
      note = "throttled: a handful of statusline redraws, not 300",
    },
    {
      wait = "_G.status():find('100%', 1, true) and _G.status():find('Indexing', 1, true)",
      note = "the last report is drawn, with the title its begin gave",
    },
    { lua = '_G.progress(1, "idx", { kind = "end" })', note = "the indexing ends" },
    { wait = "not _G.status():find('Indexing', 1, true)", note = "the segment is empty again" },
  },
  manual = {
    "With a real rust-analyzer or jdtls: the spinner moves about ten times a second and is gone when indexing ends",
  },
}
