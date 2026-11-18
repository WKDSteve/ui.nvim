-- Live check (task fileops.nvim/no-name-buffer-schliessen-und-speichern): closing the tab's last [No Name] buffer
-- does not close it and says so; with unsaved text the message offers "Save as…", which opens fileops.nvim's prompt
-- typeable in Insert mode. An unnamed modified buffer among others is asked about with Save as… / Discard / Cancel.
--
-- fileops.nvim is a stand-in: its `save_as_prompt` opens the kit's real text prompt, as fileops' first step does,
-- and records what was typed. The prompt itself is fileops' own sheet (fileops.save).

local DIALOG = [[require("lib.nvim.ui.kit.confirm").is_open()]]
local PROMPTING = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.mode() == "i"]]

---The text of the open float.
local FLOAT = [[(function()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), "\n")
    end
  end
  return ""
end)()]]

return {
  id = "tabufline.close-no-name",
  feature = "ui.tabline",
  title = "<leader>bc on the tab's last [No Name] says it cannot be closed and offers Save as…",
  task = "fileops.nvim/no-name-buffer-schliessen-und-speichern",
  engine = "rpc",
  sizes = { { rows = 30, cols = 100 } },
  steps = {
    {
      lua = [[vim.opt.shortmess:append("I"); vim.o.swapfile = false; vim.g.mapleader = " "
      _G.msgs = {}
      vim.notify = function(msg) _G.msgs[#_G.msgs + 1] = tostring(msg) end
      _G.said = function(text)
        for _, m in ipairs(_G.msgs) do
          if m:find(text, 1, true) then return true end
        end
        return false
      end
      package.loaded["fileops"] = {
        save_as_prompt = function(bufnr, on_done)
          _G.save_as_for = bufnr
          require("lib.nvim.ui.kit").input({
            title = "Save [No Name] as (file name)",
            on_submit = function(text) _G.typed = text; on_done(false) end,
            on_cancel = function() on_done(false) end,
          })
        end,
      }
      require("ui").setup({ keymaps = true })
      _G.noname = vim.api.nvim_get_current_buf()]],
      note = "the keymaps, a stand-in fileops, the startup [No Name] alone in the tab",
    },

    -- unchanged: a message, no dialog, the buffer stays
    { keys = "<Space>bc", note = "close the last, unchanged [No Name]" },
    {
      wait = [[_G.said("last buffer in this tab")]],
      note = "the message says it is the last buffer",
    },
    { expect = "not " .. DIALOG, note = "no dialog for an unchanged buffer" },
    {
      expect = [[vim.api.nvim_get_current_buf() == _G.noname and vim.api.nvim_buf_is_valid(_G.noname)]],
      note = "the same buffer stays",
    },

    -- with text: the dialog says so and offers Save as… / OK, never Discard
    { lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "0" })]] },
    { keys = "<Space>bc", note = "close it again, now with unsaved text" },
    { wait = DIALOG, note = "a dialog opens" },
    { settle = 200 },
    { screen = "last-no-name" },
    {
      expect = FLOAT
        .. [[:find("cannot be closed", 1, true) and ]]
        .. FLOAT
        .. [[:find("Save as", 1, true)
        and not ]]
        .. FLOAT
        .. [[:find("Discard", 1, true)]],
      note = "it says the buffer cannot be closed, offers Save as…, no Discard",
    },
    { keys = "<CR>", note = "OK has the focus" },
    { wait = "not " .. DIALOG },
    {
      expect = [[vim.api.nvim_get_current_buf() == _G.noname and vim.bo.modified
        and vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "0"]],
      note = "OK: the buffer and its text stay",
    },

    { keys = "<Space>bc" },
    { wait = DIALOG },
    { keys = "h<CR>", note = "the Save as… button" },
    { wait = PROMPTING, note = "fileops' prompt opens in Insert mode" },
    { input = "x.md<CR>" },
    { wait = [[_G.typed == "x.md"]], note = "what is typed reaches the prompt, not Normal mode" },
    { expect = [[_G.save_as_for == _G.noname]], note = "for the [No Name] buffer" },

    -- among others: Save as… / Discard / Cancel
    {
      lua = [[vim.cmd.edit(vim.fn.tempname() .. "-other.txt")
      vim.api.nvim_set_current_buf(_G.noname)]],
      note = "a named buffer joins the tab, back on the [No Name]",
    },
    { wait = [[#(vim.t.bufs or {}) >= 2]], note = "two buffers in the tab's list" },
    { keys = "<Space>bc" },
    { wait = DIALOG, note = "the unsaved-changes dialog" },
    {
      expect = FLOAT .. [[:find("Save as", 1, true) and ]] .. FLOAT .. [[:find("Discard", 1, true)
        and ]] .. FLOAT .. [[:find("Cancel", 1, true)]],
      note = "Save as… / Discard / Cancel",
    },
    { keys = "<Esc>" },
    { wait = "not " .. DIALOG },
    {
      expect = [[vim.api.nvim_buf_is_valid(_G.noname) and vim.bo[_G.noname].modified]],
      note = "<Esc> keeps it",
    },
  },
  judge = {
    "The last-buffer message reads as a reason, not as an error",
  },
}
