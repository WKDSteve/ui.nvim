-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.screenkey.subscribe()` -- the capture of the keystroke HUD as a public API for another
--- display (the keycast overlay of mdview.nvim). Drives real keys via `nvim_feedkeys`, as
--- TESTS/screenkey_spec.lua does, and waits for the scheduled delivery.

local screenkey = require("ui.screenkey")

---@param keys string
---@param mode? string
local function feed(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode or "x", false)
end

--- A subscription that records every entry it is handed.
---@param opts? table
---@return Ui.Screenkey.Subscription sub, { key: string, label: string, count: integer }[] got
local function recorder(opts)
  local got = {}
  local sub = screenkey.subscribe(function(entry)
    got[#got + 1] = entry
  end, opts)
  return sub, got
end

---@param got table[]
---@return string
local function keys_of(got)
  local out = {}
  for _, e in ipairs(got) do
    out[#out + 1] = e.key
  end
  return table.concat(out, " ")
end

---@param buf integer
local function wipe(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

describe("ui.screenkey.subscribe", function()
  local subs, showmode

  before_each(function()
    subs = {}
    showmode = vim.o.showmode
    vim.o.showmode = false
  end)

  after_each(function()
    for _, s in ipairs(subs) do
      s:unsubscribe()
    end
    screenkey.disable()
    screenkey.setup({
      labels = {},
      join_chars = false,
      width = 40,
      hide = { buftypes = {}, filetypes = {} },
    })
    vim.cmd("stopinsert")
    vim.o.showmode = showmode
  end)

  ---@param opts? table
  local function sub_of(opts)
    local s, got = recorder(opts)
    subs[#subs + 1] = s
    return s, got
  end

  it("attaches vim.on_key only while somebody listens", function()
    assert.equals(0, screenkey.subscriber_count())
    local a = sub_of()
    local b = sub_of({ scope = "all" })
    assert.equals(2, screenkey.subscriber_count())
    a:unsubscribe()
    a:unsubscribe() -- idempotent
    assert.equals(1, screenkey.subscriber_count())
    assert.is_false(a:active())
    b:unsubscribe()
    assert.equals(0, screenkey.subscriber_count())

    -- an ended subscription gets no more keys
    feed("j")
    vim.wait(100)
    for _, s in ipairs({ a, b }) do
      assert.same({}, s:entries())
    end
  end)

  it("hands each key keytrans'd, with its label and the repeat count", function()
    screenkey.setup({ labels = { ["<Esc>"] = "Esc" } })
    local s, got = sub_of({ scope = "all" })
    feed("<Esc>")
    feed("j")
    feed("j")
    vim.wait(300, function()
      return #got == 3
    end)
    assert.same({ key = "<Esc>", label = "Esc", count = 1 }, got[1])
    assert.same({ key = "j", label = "j", count = 1 }, got[2])
    assert.same({ key = "j", label = "j", count = 2 }, got[3], "the same key again counts up")
    assert.same(
      { { key = "<Esc>", label = "Esc", count = 1 }, { key = "j", label = "j", count = 2 } },
      s:entries()
    )
    assert.equals("Esc j" .. "\xC3\x97" .. "2", s:text(40))
    s:clear()
    assert.same({}, s:entries())
  end)

  it("text() joins typed text when asked, whatever the HUD's join_chars is", function()
    screenkey.setup({ join_chars = false })
    local s, got = sub_of({ scope = "all" })
    feed("j")
    feed("k")
    feed("<Esc>")
    vim.wait(300, function()
      return #got == 3
    end)
    assert.equals("j k <Esc>", s:text(40))
    assert.equals("jk <Esc>", s:text(40, { join_chars = true }))
    screenkey.setup({ join_chars = true })
    assert.equals("jk <Esc>", s:text(40))
    assert.equals("j k <Esc>", s:text(40, { join_chars = false }))
  end)

  it("caps the list at max_entries, dropping the oldest", function()
    local s, got = sub_of({ max_entries = 2 })
    feed("j")
    feed("k")
    feed("l")
    vim.wait(300, function()
      return #got == 3
    end)
    assert.same({ "k", "l" }, { s:entries()[1].key, s:entries()[2].key })
  end)

  it("scope normal leaves out what is typed in Insert mode, the keys around it stay", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local _, normal = sub_of({ scope = "normal" })
    local _, all = sub_of({ scope = "all" })
    feed("ihello<Esc>")
    feed("j")
    vim.wait(300, function()
      return #all >= 8
    end)
    -- `i` is typed in Normal mode, `<Esc>` in Insert mode
    assert.equals("i h e l l o <Esc> j", keys_of(all))
    assert.equals("i j", keys_of(normal))
    wipe(buf)
  end)

  it("scope normal shows the key that opens the command line, never what is typed there", function()
    local _, normal = sub_of({ scope = "normal" })
    local _, protected = sub_of({ scope = "insert_protected" })
    local _, all = sub_of({ scope = "all" })
    feed(":let g:ui_sk_spec = 'tok'<CR>")
    feed("j")
    vim.wait(300, function()
      return #all > 0 and all[#all].key == "j"
    end)
    assert.equals("tok", vim.g.ui_sk_spec)
    vim.g.ui_sk_spec = nil
    -- `:` is a Normal-mode key; `let ...<CR>` is typed on the command line
    assert.equals(": j", keys_of(normal))
    assert.truthy(keys_of(protected):find("' t o k ' <CR> j", 1, true), keys_of(protected))
    assert.truthy(keys_of(all):find("' t o k ' <CR> j", 1, true), keys_of(all))
  end)

  it("scope normal leaves out a search", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "secret" })
    local _, normal = sub_of({ scope = "normal" })
    local _, all = sub_of({ scope = "all" })
    feed("/secret<CR>")
    feed("k")
    vim.wait(300, function()
      return #all > 0 and all[#all].key == "k"
    end)
    assert.equals("/ k", keys_of(normal))
    wipe(buf)
  end)

  it("scope normal leaves out Select mode (a snippet placeholder being overwritten)", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "placeholder" })
    local _, normal = sub_of({ scope = "normal" })
    local _, all = sub_of({ scope = "all" })
    -- `v` `l` in Visual mode, <C-g> switches to Select, `x` is typed over the selection
    feed("vl<C-g>x")
    vim.wait(300, function()
      return #all >= 4
    end)
    assert.equals("xaceholder", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    assert.equals("v l <C-G>", keys_of(normal))
    assert.truthy(keys_of(all):find("<C-G> x", 1, true), keys_of(all))
    vim.cmd("stopinsert")
    wipe(buf)
  end)

  it("insert_protected leaves out Terminal mode (a sudo/ssh password); all keeps it", function()
    -- A real :terminal would start a shell, which the specs may not: the mode is what decides.
    local get_mode = vim.api.nvim_get_mode
    local _, normal = sub_of({ scope = "normal" })
    local _, protected = sub_of({ scope = "insert_protected" })
    local _, all = sub_of({ scope = "all" })
    vim.api.nvim_get_mode = function()
      return { mode = "t", blocking = false }
    end
    feed("j")
    vim.api.nvim_get_mode = get_mode
    feed("k")
    vim.wait(300, function()
      return #all == 2
    end)
    assert.equals("k", keys_of(normal))
    assert.equals("k", keys_of(protected))
    assert.equals("j k", keys_of(all))
  end)

  it("a mode that cannot be told counts as the most private one", function()
    local get_mode = vim.api.nvim_get_mode
    local _, protected = sub_of({ scope = "insert_protected" })
    local _, all = sub_of({ scope = "all" })
    vim.api.nvim_get_mode = function()
      error("no mode")
    end
    feed("j")
    vim.api.nvim_get_mode = get_mode
    vim.wait(300, function()
      return #all == 1
    end)
    assert.equals("", keys_of(protected))
  end)

  it("on_drop tells a subscriber that raised that it was removed", function()
    local notify = vim.notify
    vim.notify = function() end
    local dropped
    local bad = screenkey.subscribe(function()
      error("boom")
    end, {
      on_drop = function(err)
        dropped = tostring(err)
      end,
    })
    subs[#subs + 1] = bad
    feed("j")
    vim.wait(300, function()
      return dropped ~= nil
    end)
    vim.notify = notify
    assert.truthy(dropped:find("boom", 1, true), dropped)
    assert.is_false(bad:active())
  end)

  it("the HUD whose render() raised is off for real and can be enabled again", function()
    local surface = require("ui.kit.surface")
    local open = surface.open
    local notify = vim.notify
    vim.notify = function() end
    surface.open = function()
      error("no float")
    end
    screenkey.enable()
    feed("j")
    vim.wait(300, function()
      return not screenkey.is_enabled()
    end)
    surface.open = open
    vim.notify = notify
    assert.is_false(screenkey.is_enabled())
    assert.equals(0, screenkey.subscriber_count())
    screenkey.enable()
    feed("k")
    vim.wait(300, function()
      return screenkey.surface() ~= nil
    end)
    assert.is_true(screenkey.is_enabled())
    assert.is_not_nil(screenkey.surface())
  end)

  for _, fn_name in ipairs({ "inputsecret", "input" }) do
    it("leaves out what is typed into " .. fn_name .. "() unless the scope is all", function()
      local _, normal = sub_of({ scope = "normal" })
      local _, protected = sub_of({ scope = "insert_protected" })
      local _, all = sub_of({ scope = "all" })
      feed("j")
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("hunter2<CR>", true, false, true),
        "t",
        false
      )
      local answer = vim.api.nvim_call_function(fn_name, { "pw: " })
      feed("k")
      vim.wait(300, function()
        return #all > 0 and all[#all].key == "k"
      end)
      assert.equals("hunter2", answer)
      -- the keys right before and after the prompt are there, nothing of the prompt
      assert.equals("j k", keys_of(normal))
      assert.equals("j k", keys_of(protected))
      assert.truthy(keys_of(all):find("h u n t e r 2 <CR>", 1, true), keys_of(all))
    end)
  end

  it("leaves out a buftype=prompt buffer for normal and insert_protected", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "prompt"
    vim.api.nvim_set_current_buf(buf)
    local _, normal = sub_of({ scope = "normal" })
    local _, protected = sub_of({ scope = "insert_protected" })
    local _, all = sub_of({ scope = "all" })
    feed("ipw") -- feedkeys "x" ends Insert mode with an <Esc> of its own
    vim.wait(300, function()
      return #all == 4
    end)
    assert.equals("", keys_of(normal))
    assert.equals("", keys_of(protected))
    assert.equals("i p w <Esc>", keys_of(all))
    vim.cmd("stopinsert")
    wipe(buf)
  end)

  it("insert_protected shows Insert-mode text of an ordinary buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local _, protected = sub_of({ scope = "insert_protected" })
    feed("iab<Esc>")
    vim.wait(300, function()
      return #protected == 4
    end)
    assert.equals("i a b <Esc>", keys_of(protected))
    wipe(buf)
  end)

  it("the HUD is one subscriber among others", function()
    local _, got = sub_of()
    screenkey.enable()
    assert.equals(2, screenkey.subscriber_count())
    feed("j")
    vim.wait(300, function()
      return #got == 1 and screenkey.surface() ~= nil
    end)
    screenkey.disable()
    assert.equals(
      1,
      screenkey.subscriber_count(),
      "disabling the HUD leaves the other subscription"
    )
    feed("k")
    vim.wait(300, function()
      return #got == 2
    end)
    assert.equals("j k", keys_of(got))
  end)

  it("a subscriber that raises is removed with a warning, the others go on", function()
    local warned
    local notify = vim.notify
    vim.notify = function(msg, level)
      warned = { msg = msg, level = level }
    end
    local bad = screenkey.subscribe(function()
      error("boom")
    end)
    subs[#subs + 1] = bad
    local _, got = sub_of()
    feed("j")
    vim.wait(300, function()
      return #got == 1 and warned ~= nil
    end)
    vim.notify = notify
    assert.is_false(bad:active())
    assert.truthy(warned.msg:find("a key subscriber failed and was removed", 1, true), warned.msg)
    assert.equals(vim.log.levels.WARN, warned.level)
    assert.equals(1, #got)
  end)

  it("refuses a bad callback, scope or max_entries", function()
    assert.has_error(function()
      screenkey.subscribe("x")
    end, "ui.screenkey.subscribe: callback must be a function, got string")
    assert.has_error(function()
      screenkey.subscribe(function() end, { scope = "insert" })
    end, 'ui.screenkey.subscribe: scope must be one of normal, insert_protected, all, got "insert"')
    assert.has_error(function()
      screenkey.subscribe(function() end, { max_entries = 0 })
    end, "ui.screenkey.subscribe: max_entries must be a positive integer, got 0")
    assert.has_error(function()
      screenkey.subscribe(function() end, { on_drop = 1 })
    end, "ui.screenkey.subscribe: on_drop must be a function, got number")
    assert.equals(0, screenkey.subscriber_count())
  end)
end)
