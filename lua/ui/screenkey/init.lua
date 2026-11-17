---@module 'ui.screenkey'
--- In-editor keystroke HUD -- shows the keys currently being pressed in a
--- small corner float, for recording demos/GIFs of this plugin fleet (the
--- live/animated equivalent of the screenshots several sibling READMEs
--- already ship, e.g. `cmdlog.nvim/docs/assets/Cmdlog-Picker-UI.png`). Not a
--- daily-driver feature -- off by default, and stays off until `:UI
--- screenkey` (or `M.enable()`) turns it on for the session.
---
--- Built entirely on native Neovim primitives, no missing building block:
--- `vim.on_key()` intercepts every keypress, `vim.fn.keytrans()` formats the
--- raw byte sequence into human-readable form (`<C-w>`, `<Esc>`, ...). The
--- float itself is `ui.kit.surface` -- the same primitive `ui.kit.toast`
--- reflows into a corner, no new float-window mechanics invented here.
---
--- The capture is public (`M.subscribe`, docs/screenkey.md): the HUD is one
--- subscriber, another display (mdview.nvim's keycast overlay) can be another.
--- The `vim.on_key()` hook is registered only while there is a subscriber
--- (mirrors `ui.statusline.modules.macro_counter`'s own `RecordingEnter`/
--- `RecordingLeave`-bracketed hook) -- a disabled screenkey with nobody else
--- listening costs nothing on every keystroke, not just "renders nothing".
---
--- Privacy: a recording is when a password typed into a prompt costs the most, so the
--- keys typed into a buffer marked as holding a secret (`ui.kit.surface.is_secret`: a
--- `ui.kit.input` with `secret = true`, a `ui.kit.sheet` with a secret field) never
--- reach the HUD. What is not the kit's cannot be told from an ordinary prompt (a plugin's own
--- password question is a plain `input()`), so the HUD stays silent for all of them: while
--- `vim.fn.input()` (command-line type `@`) or `vim.fn.inputsecret()` (type `-`, which is also
--- `:insert`/`:append`) is waiting, in a `buftype=prompt` buffer, and in any buffer of
--- `setup({ hide = { buftypes = {...}, filetypes = {...} } })`.

local surface = require("ui.kit.surface")
local debounce = require("lib.nvim.debounce")
local normalize = require("lib.nvim.normalize")
local autocmd = require("lib.nvim.bindings.autocmd")
local notify = require("lib.nvim.notify").create("[ui.screenkey]")

local M = {}

--- `M.setup(opts)`'s own parameter shape -- every field optional, overriding
--- just the ones a host passes.
---@class Ui.Screenkey.Opts
---@field fade_ms? integer
---@field width? integer
---@field height? integer
---@field margin? integer
---@field max_entries? integer
---@field theme? string|table|nil
---@field labels? table<string, string>
---@field join_chars? boolean
---@field hide? { buftypes?: string[], filetypes?: string[] } # buffers whose keys are never shown, on top of the built-in ones; a given list replaces that field's earlier one (`{}` empties it), unless it holds an invalid entry: then its valid entries are added to the earlier list

---@class Ui.Screenkey.Config
---@field fade_ms integer # how long the HUD stays up after the last keystroke
---@field width integer # float width in columns
---@field height integer # float height in rows -- one line, MVP
---@field margin integer # columns from the right edge / rows above the cmdline
---@field max_entries integer # rolling cap on tracked key entries, before display-width truncation
---@field theme string|table|nil # forwarded to ui.kit.surface's theme resolver
---@field labels table<string, string> # keytrans() name -> what to show instead, e.g. { ["<Space>"] = "\xE2\x90\xA3" (U+2423), ["<CR>"] = "\xE2\x8F\x8E" (U+23CE) }
---@field join_chars boolean # run plain characters together ("todo.md") instead of one chip per key ("t o d o . m d")
---@field hide_buftypes table<string, true> # keys typed into a buffer of these 'buftype's are not shown (`prompt` always is)
---@field hide_filetypes table<string, true> # same for 'filetype's
local cfg = {
  fade_ms = 2000,
  width = 40,
  height = 1,
  margin = 2,
  max_entries = 30,
  theme = nil,
  labels = {},
  join_chars = false,
  hide_buftypes = {},
  hide_filetypes = {},
}

--- The keys `M.setup()` understands; any other is reported by `M.health_issues()`.
local KNOWN_OPTS = {
  fade_ms = true,
  width = true,
  height = true,
  margin = true,
  max_entries = true,
  theme = true,
  labels = true,
  join_chars = true,
  hide = true,
}

---@type boolean
local enabled = false
---@type Ui.Kit.Surface|nil
local surf = nil
---@type Ui.Screenkey.Subscription|nil
--- The HUD's own subscription (see `M.subscribe`): it holds the entries the HUD shows.
local hud = nil
---@type string[]
--- Rejected values from the last `M.setup()` call -- an invalid single value
--- keeps `cfg`'s current one instead of corrupting it, surfaced through
--- `:checkhealth ui` rather than raised (ERR-22).
local setup_issues = {}

---@internal
--- Close the float and drop every tracked entry -- the fade's own end state,
--- and what `M.disable()` resets to as well.
---@return nil
local function clear()
  if surf then
    surf:close()
    surf = nil
  end
  if hud then
    hud:clear()
  end
end

---@internal
--- One debounce handle per `cfg.fade_ms` -- rebuilt in `M.setup()` whenever
--- that value changes, since `lib.nvim.debounce.new()` bakes its `ms`
--- argument in at creation rather than reading it live per call.
local function build_fader()
  return debounce.new(clear, cfg.fade_ms)
end

local fader = build_fader()

---@internal
--- The formatted display key×count suffix as `\xC3\x97` (U+00D7 MULTIPLICATION
--- SIGN), written as explicit bytes rather than a literal glyph -- same
--- reason `ui.tabline.utils`'s rounded-cap codepoints and
--- `ui.statusline.modules.macro_counter`'s middle dot are: an editor/encoding
--- pass has silently dropped literal multi-byte glyphs from this codebase
--- before.
local TIMES = "\xC3\x97"

---@internal
--- What one entry shows: its `cfg.labels` replacement when there is one,
--- the keytrans() name otherwise.
---@param key string
---@return string
local function label_of(key)
  local l = cfg.labels[key]
  if type(l) == "string" and l ~= "" then
    return l
  end
  return key
end

---@internal
--- With `cfg.join_chars`, a run of single presses whose display is not a
--- `<...>` keycode is one chip ("todo.md" rather than "t o d o . m d"), so
--- typed text reads as text while `<Esc>`, `<C-w>` and repeat counts still
--- stand apart. A label counts as text too: `<Space>` shown as U+2423
--- joins its neighbours, an unlabelled `<Space>` does not.
--- A short repeat ("pp" in "app", "ee" in "see") is spelled out inside the
--- run; from JOIN_REPEAT_MAX + 1 on it is a held key and stays a `key×N`
--- chip of its own, so "jjjjjjjj" does not paint a wall of j.
---@param display string
---@param count integer
---@return boolean
local JOIN_REPEAT_MAX = 3
local function joinable(display, count)
  return cfg.join_chars and count <= JOIN_REPEAT_MAX and display:match("^<.+>$") == nil
end

---@internal
--- Clip `text` to `max_w` display columns by dropping leading *characters*
--- (never bytes: a byte clip could cut a multi-byte glyph such as a U+2423
--- label in half and put invalid UTF-8 into the buffer), keeping at least
--- one. Binary search over the drop count rather than one character per
--- step: this runs on every keystroke once a joined run outgrows the HUD
--- (any long insert-mode line with `join_chars`), and shaving a character
--- at a time cost two Vimscript calls per character per keystroke -- 3.6 ms
--- per key for a 450-character run of labelled keys, measured headless --
--- where log2(n) probes cost 0.05 ms. Dropping more never widens the
--- remainder, so the fit predicate is monotonic.
---@param text string
---@param max_w integer
---@return string
local function clip_leading(text, max_w)
  if vim.fn.strdisplaywidth(text) <= max_w then
    return text
  end
  local n = vim.fn.strchars(text)
  if n <= 1 then
    return text
  end
  local lo, hi = 1, n - 1 -- drop at least one character, keep at least one
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if vim.fn.strdisplaywidth(vim.fn.strcharpart(text, mid)) <= max_w then
      hi = mid
    else
      lo = mid + 1
    end
  end
  return vim.fn.strcharpart(text, lo)
end

---@internal
--- Build the one-line display string from `entries`, dropping the oldest
--- entries (never the newest) until it fits `width` display columns -- the most
--- recent keystroke is always the one worth seeing.
---@param entries { key: string, count: integer }[]
---@param width integer
---@return string
local function build_text(entries, width)
  local parts = {}
  local open = false -- whether parts[#parts] is a run that may still grow
  for _, e in ipairs(entries) do
    local display = label_of(e.key)
    if joinable(display, e.count) then
      local run = display:rep(e.count)
      if open then
        parts[#parts] = parts[#parts] .. run
      else
        parts[#parts + 1] = run
        open = true
      end
    else
      parts[#parts + 1] = (e.count > 1) and (display .. TIMES .. e.count) or display
      open = false
    end
  end

  local max_w = math.max(1, width)
  local text = table.concat(parts, " ")
  while #parts > 1 and vim.fn.strdisplaywidth(text) > max_w do
    table.remove(parts, 1)
    text = table.concat(parts, " ")
  end
  -- A single part alone overflows: a long <Cmd>...<CR> sequence, or with
  -- `join_chars` any typed command line.
  return clip_leading(text, max_w)
end

---@internal
--- Bottom-right corner, same margin-from-edges arithmetic
--- `ui.kit.compare`/`ui.kit.layout` already use for "usable rows above the
--- cmdline" (`vim.o.lines - (vim.o.cmdheight or 1)`).
---@return integer row, integer col
local function corner_geometry()
  local usable_lines = vim.o.lines - (vim.o.cmdheight or 1)
  local row = math.max(0, usable_lines - cfg.height - cfg.margin)
  local col = math.max(0, vim.o.columns - cfg.width - cfg.margin)
  return row, col
end

---@internal
--- Reposition the live HUD at its current corner -- the editor may have been
--- resized since it was opened (PERF-92: geometry must never stay pinned to
--- the size it happened to open at). No-op while closed.
---@return nil
local function reposition()
  if not (surf and surf:is_valid()) then
    return
  end
  local row, col = corner_geometry()
  pcall(vim.api.nvim_win_set_config, surf.winid, {
    relative = "editor",
    row = row,
    col = col,
    width = cfg.width,
    height = cfg.height,
  })
end

---@internal
--- Open the float on first render, `set_lines` on every one after -- mirrors
--- `ui.kit.toast`'s own open-once-then-update shape, minus the stacking (one
--- screenkey HUD, not several). Repositions the existing float every time
--- too, so a `VimResized` while the HUD is up (it can stay up for as long as
--- keys keep coming) is reflected on the very next keystroke rather than
--- leaving it pinned to stale coordinates (PERF-92).
---@return nil
local function render()
  local text = build_text(hud and hud._entries or {}, cfg.width - 2) -- inside the border/padding

  if surf and surf:is_valid() then
    reposition()
    surf:set_lines({ text })
    return
  end

  local row, col = corner_geometry()
  surf = surface.open({
    lines = { text },
    width = cfg.width,
    height = cfg.height,
    relative = "editor",
    row = row,
    col = col,
    title = "Screenkey",
    theme = cfg.theme,
    enter = false, -- never steal focus
    focusable = false,
  })
end

---@internal
--- Whether a buffer's 'filetype' is on the `hide.filetypes` set. The option can hold several
--- names joined by dots (`pw.local`: Neovim treats each part as a filetype of its own), so
--- the whole value matches and so does any single part; an exact lookup alone would show
--- the keys typed into `pw.local` although `pw` is listed.
---@param filetype string # the buffer's 'filetype' (may be empty or dotted)
---@return boolean
local function hidden_filetype(filetype)
  -- Asked for every key: nothing to look up while no filetype is listed (the default).
  if next(cfg.hide_filetypes) == nil then
    return false
  end
  if cfg.hide_filetypes[filetype] == true then
    return true
  end
  for part in filetype:gmatch("[^.]+") do
    if cfg.hide_filetypes[part] == true then
      return true
    end
  end
  return false
end

---@internal
--- Whether what is typed right now must stay off the HUD: a prompt of the kit marked as
--- secret, a waiting `input()`/`inputsecret()` (command-line type `@` / `-`), a `buftype=prompt`
--- buffer, or a buffer of the `hide` lists. Asked synchronously in `on_key`, see there.
---@return boolean
local function protected()
  if surface.is_secret() then
    return true
  end
  local cmdtype = vim.fn.getcmdtype()
  if cmdtype == "@" or cmdtype == "-" then
    return true
  end
  local bo = vim.bo[vim.api.nvim_get_current_buf()]
  return bo.buftype == "prompt"
    or cfg.hide_buftypes[bo.buftype] == true
    or hidden_filetype(bo.filetype)
end

---@alias Ui.Screenkey.Scope
---| "normal" # keys typed outside Insert, Replace and Terminal mode (Normal, Visual, Operator-pending, the command line)
---| "insert_protected" # every mode, but never a protected key (what the HUD shows)
---| "all" # every key, protected ones too

--- One captured key as a subscriber sees it.
---@class Ui.Screenkey.Entry
---@field key string # the keytrans() name, e.g. `<C-W>`, `<Esc>`, `w`
---@field label string # what to show: the `labels` replacement of `key`, else `key`
---@field count integer # how many times in a row it was pressed (1 for a new key)

--- A handle `M.subscribe()` returns.
---@class Ui.Screenkey.Subscription
---@field scope Ui.Screenkey.Scope
---@field package _cb fun(entry: Ui.Screenkey.Entry, sub: Ui.Screenkey.Subscription)
---@field package _max integer|nil
---@field package _entries Ui.Screenkey.Entry[]
---@field package _live boolean
local Subscription = {}
Subscription.__index = Subscription

---The entries since the last `clear()`, oldest first (at most `max_entries`). A copy.
---@return Ui.Screenkey.Entry[]
function Subscription:entries()
  return vim.deepcopy(self._entries)
end

---Drop the recorded entries (the next key starts a new list).
---@return nil
function Subscription:clear()
  self._entries = {}
end

---The entries as one line of at most `width` display columns, formatted as the HUD formats
---them (labels, `key×N` repeats, `join_chars` runs), the oldest dropped first.
---@param width integer
---@return string
function Subscription:text(width)
  return build_text(self._entries, width)
end

---Whether this subscription still receives keys.
---@return boolean
function Subscription:active()
  return self._live
end

--- The scopes `M.subscribe()` accepts.
M.SCOPES = { "normal", "insert_protected", "all" }

local CAPTURE_NS = vim.api.nvim_create_namespace("ui_screenkey_capture")
---@type Ui.Screenkey.Subscription[]
local subscribers = {}

---@internal
--- Record `trans` in a subscription's list and return the entry it added or counted up.
---@param sub Ui.Screenkey.Subscription
---@param trans string
---@return Ui.Screenkey.Entry
local function push(sub, trans)
  local list = sub._entries
  local last = list[#list]
  if last and last.key == trans then
    last.count = last.count + 1
    return last
  end
  local entry = { key = trans, label = label_of(trans), count = 1 }
  list[#list + 1] = entry
  while #list > (sub._max or cfg.max_entries) do
    table.remove(list, 1)
  end
  return entry
end

---@internal
--- The `vim.on_key()` callback of the capture, registered while there is at least one
--- subscriber. Deliberately minimal outside `vim.schedule` -- the raw callback runs in
--- Neovim's own input-processing path, not a normal call stack, so the state mutation and
--- every subscriber call are deferred onto the main loop.
---
--- What a key is (protected, typed in Insert mode) is asked HERE, before the `vim.schedule`:
--- the key that submits a prompt (`<CR>`) closes it, and by the time the scheduled work ran
--- the current buffer and mode would be other ones and the key would be shown after all.
---@param key string # post-mapping raw keycode, per vim.on_key()'s own contract
---@return nil
local function on_key(key)
  if key == "" then
    return
  end
  -- An error here would make Neovim drop this callback for good, and a key whose protection
  -- could not be told is one that must not be shown: both end the same way, as protected.
  local told, hidden = pcall(protected)
  hidden = hidden == true or not told
  local ok_mode, mode = pcall(function()
    return vim.api.nvim_get_mode().mode:sub(1, 1)
  end)
  local insert_like = not ok_mode or mode == "i" or mode == "R" or mode == "t"
  local accepts = {
    all = true,
    insert_protected = not hidden,
    normal = not hidden and not insert_like,
  }
  vim.schedule(function()
    local ok, trans = pcall(vim.fn.keytrans, key)
    if not ok or trans == nil or trans == "" then
      return
    end
    -- A raw terminal code (`<t_..>`: a key the terminal sent in a form
    -- Neovim has no name for) means nothing to a viewer; leave it out.
    if trans:sub(1, 3) == "<t_" then
      return
    end
    -- A copy: a callback may unsubscribe (itself or another one) while this runs.
    for _, sub in ipairs({ unpack(subscribers) }) do
      if sub._live and accepts[sub.scope] then
        local entry = push(sub, trans)
        local fine, err = pcall(sub._cb, vim.deepcopy(entry), sub)
        if not fine then
          sub:unsubscribe()
          pcall(notify.warn, ("a key subscriber failed and was removed: %s"):format(tostring(err)))
        end
      end
    end
  end)
end

---Stop receiving keys. The `vim.on_key()` hook is detached with the last subscription.
---Idempotent.
---@return nil
function Subscription:unsubscribe()
  if not self._live then
    return
  end
  self._live = false
  for i, sub in ipairs(subscribers) do
    if sub == self then
      table.remove(subscribers, i)
      break
    end
  end
  if #subscribers == 0 then
    vim.on_key(nil, CAPTURE_NS)
  end
end

---Receive the keys pressed in Neovim, formatted as the HUD shows them (`keytrans()` names,
---`labels`, repeat counts), for another display -- the HUD itself is one subscriber, the
---keycast overlay of mdview.nvim another. `callback(entry, sub)` runs on the main loop after
---each accepted key with a copy of the entry it added or counted up; `sub:entries()` and
---`sub:text(width)` give the whole list. The `vim.on_key()` hook is attached only while
---there is at least one subscription.
---
---`opts.scope` (default `"insert_protected"`) decides which keys a subscription gets:
---`"normal"` only keys typed outside Insert, Replace and Terminal mode, and never a
---protected one; `"insert_protected"` every mode but never a protected key; `"all"` every
---key. A protected key is one typed into a secret `ui.kit` prompt or sheet, while
---`input()`/`inputsecret()` waits (command-line type `@`/`-`), into a `buftype=prompt`
---buffer or into a buffer of `setup({ hide = ... })`. `opts.max_entries` caps the list
---(default: the `max_entries` of `setup()`, read live).
---
---A callback that raises is unsubscribed (and a warning shown), so one broken consumer
---cannot cost a message per keystroke.
---@param callback fun(entry: Ui.Screenkey.Entry, sub: Ui.Screenkey.Subscription)
---@param opts? { scope?: Ui.Screenkey.Scope, max_entries?: integer }
---@return Ui.Screenkey.Subscription
function M.subscribe(callback, opts)
  if type(callback) ~= "function" then
    error(("ui.screenkey.subscribe: callback must be a function, got %s"):format(type(callback)), 2)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error(("ui.screenkey.subscribe: opts must be a table, got %s"):format(type(opts)), 2)
  end
  opts = opts or {}
  local scope = opts.scope or "insert_protected"
  if not vim.tbl_contains(M.SCOPES, scope) then
    error(
      ("ui.screenkey.subscribe: scope must be one of %s, got %s"):format(
        table.concat(M.SCOPES, ", "),
        vim.inspect(scope)
      ),
      2
    )
  end
  local max = opts.max_entries
  if max ~= nil and (type(max) ~= "number" or max < 1 or max % 1 ~= 0) then
    error(
      ("ui.screenkey.subscribe: max_entries must be a positive integer, got %s"):format(
        vim.inspect(max)
      ),
      2
    )
  end
  local sub = setmetatable({
    scope = scope,
    _cb = callback,
    _max = max,
    _entries = {},
    _live = true,
  }, Subscription)
  subscribers[#subscribers + 1] = sub
  if #subscribers == 1 then
    vim.on_key(on_key, CAPTURE_NS)
  end
  return sub
end

---The number of live subscriptions (the HUD's included) -- for health and tests.
---@return integer
function M.subscriber_count()
  return #subscribers
end

---@internal
--- Validate one integer field of `opts` and apply it to `cfg`, or reject it
--- and record why -- an invalid value keeps `cfg`'s current one rather than
--- being accepted as-is (ERR-22).
---@param opts Ui.Screenkey.Opts
---@param field "width"|"height"|"margin"|"max_entries"|"fade_ms"
---@param min integer
---@return boolean applied
local function apply_int(opts, field, min)
  local v = opts[field]
  if v == nil then
    return false
  end
  local ok, n, err = normalize.as_int(field, v, min, false)
  if ok then
    cfg[field] = n
    return true
  end
  setup_issues[#setup_issues + 1] = ("%s (kept %s)"):format(
    err or (field .. " is invalid"),
    tostring(cfg[field])
  )
  return false
end

--- Stands for "a gap in the list" where the first bad entry of a `hide` list is kept (a real
--- `vim.NIL` entry is a bad entry of its own).
local GAP = {}

---@internal
--- Whether every key of `t` is a positive integer: a list, possibly with gaps.
---@param t table
---@return boolean
local function array_like(t)
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
  end
  return true
end

---Override the shipped tunables. Safe to call before or after `M.enable()`;
---a `fade_ms` change takes effect on the next keystroke's fade, not
---retroactively on one already pending. An invalid value (wrong type, or
---below its minimum) is rejected and `cfg` keeps its current value; see
---`M.health_issues()`.
---@param opts? Ui.Screenkey.Opts
---@return nil
function M.setup(opts)
  setup_issues = {}
  -- Not a table (`setup("x")`, `setup(5)`): indexing or iterating it would raise, and there is
  -- nothing to merge, so the current settings stay.
  if opts ~= nil and type(opts) ~= "table" then
    setup_issues[1] = ("setup() takes a table of options (got %s) -- ignored"):format(
      vim.inspect(opts)
    )
    return
  end
  opts = opts or {}

  apply_int(opts, "width", 1)
  apply_int(opts, "height", 1)
  apply_int(opts, "margin", 0)
  apply_int(opts, "max_entries", 1)
  if opts.theme ~= nil then
    cfg.theme = opts.theme
  end
  if opts.labels ~= nil then
    if type(opts.labels) == "table" then
      local clean = {}
      for k, v in pairs(opts.labels) do
        if type(k) ~= "string" or type(v) ~= "string" then
          setup_issues[#setup_issues + 1] = ("labels[%s] must map a keytrans() name to a string (dropped)"):format(
            tostring(k)
          )
        -- nvim_buf_set_lines rejects any line containing "\n" -- a label with
        -- one would crash render() on the very first keystroke that uses it
        -- (surface.open()'s own initial set_lines), not just render wrong.
        elseif v:find("\n", 1, true) then
          setup_issues[#setup_issues + 1] = ("labels[%s] must not contain a newline (dropped)"):format(
            tostring(k)
          )
        else
          -- Store under the exact spelling keytrans() will hand on_key():
          -- it writes `<C-W>`, `<lt>`, `<Space>`, while a host naturally
          -- writes the mapping form (`<C-w>`, `<`, `<leader>`). Round-trip
          -- through replace_termcodes so both spellings hit the same entry;
          -- a plain character or an already-canonical name maps to itself.
          local ok_c, canon = pcall(function()
            return vim.fn.keytrans(vim.api.nvim_replace_termcodes(k, true, true, true))
          end)
          clean[(ok_c and canon ~= "") and canon or k] = v
        end
      end
      cfg.labels = clean
    else
      setup_issues[#setup_issues + 1] = ("labels must be a table (kept %d entries)"):format(
        vim.tbl_count(cfg.labels)
      )
    end
  end
  if opts.join_chars ~= nil then
    if type(opts.join_chars) == "boolean" then
      cfg.join_chars = opts.join_chars
    else
      setup_issues[#setup_issues + 1] = ("join_chars must be a boolean (kept %s)"):format(
        tostring(cfg.join_chars)
      )
    end
  end
  for key in pairs(opts) do
    if not KNOWN_OPTS[key] then
      setup_issues[#setup_issues + 1] = ("%s is not a known option (ignored)"):format(tostring(key))
    end
  end
  local hide_from = #setup_issues + 1
  if opts.hide ~= nil then
    if type(opts.hide) == "table" then
      for key in pairs(opts.hide) do
        if key ~= "buftypes" and key ~= "filetypes" then
          setup_issues[#setup_issues + 1] = ("hide.%s is not a known key (buftypes, filetypes)"):format(
            tostring(key)
          )
        end
      end
      for field, target in pairs({ buftypes = "hide_buftypes", filetypes = "hide_filetypes" }) do
        local list, set = opts.hide[field], {}
        if list == nil then
          set = cfg[target]
        elseif type(list) == "table" and (next(list) == nil or array_like(list)) then
          -- the given list REPLACES that field's earlier one (`{}` empties it). With a bad
          -- entry the list is not trusted to be a complete replacement, so what it holds
          -- ADDS to the current list instead: a privacy setting must never hide less than
          -- the caller asked for (the valid entries) or than it did before (the old ones).
          -- A gap (`{ vim.env.X, "pw" }` with X unset) is a bad entry like any other.
          local bad = (next(list) ~= nil and not vim.islist(list)) and GAP or nil
          for _, name in pairs(list) do
            if type(name) == "string" and name ~= "" then
              set[name] = true
            elseif bad == nil then
              bad = name
            end
          end
          if bad ~= nil then
            setup_issues[#setup_issues + 1] = ("hide.%s entries must be non-empty strings, got %s (the valid ones were added to the current list)"):format(
              field,
              bad == GAP and "a gap" or vim.inspect(bad)
            )
            for name in pairs(cfg[target]) do
              set[name] = true
            end
          end
        else
          setup_issues[#setup_issues + 1] = ("hide.%s must be a list of strings (kept the current one)"):format(
            field
          )
          set = cfg[target]
        end
        cfg[target] = set
      end
    else
      setup_issues[#setup_issues + 1] =
        "hide must be a table { buftypes, filetypes } (kept the current one)"
    end
  end
  local hide_to = #setup_issues
  if apply_int(opts, "fade_ms", 1) then
    fader.cancel()
    fader = build_fader()
  end
  -- `hide` is a privacy setting: a mistake in it must not wait for someone to run
  -- :checkhealth, while the keys it was meant to hide are on a recording. Last, and guarded: a
  -- broken `vim.notify` override must not keep the settings above from being applied.
  if hide_to >= hide_from then
    pcall(notify.warn, table.concat(setup_issues, "; ", hide_from, hide_to))
  end
end

---Rejected `M.setup()` values from the last call, one message per rejected
---field -- empty when every field validated. For `:checkhealth ui`.
---@return string[]
function M.health_issues()
  return vim.deepcopy(setup_issues)
end

---Turn the HUD on: registers the `vim.on_key()` hook and a `VimResized`
---repositioner (the HUD can sit open, updated in place, for as long as keys
---keep coming -- a resize during that window must not leave it pinned to
---stale coordinates; PERF-92). Idempotent.
---@return nil
function M.enable()
  if enabled then
    return
  end
  enabled = true
  hud = M.subscribe(function()
    if not enabled then
      return
    end
    render()
    fader.call()
  end, { scope = "insert_protected" })
  local group = autocmd.group("ui_screenkey_resize", true)
  autocmd.create("VimResized", reposition, {
    group = group,
    desc = "ui.screenkey: keep the HUD pinned to its corner",
  })
end

---Turn the HUD off: detaches the hook and closes/clears the float.
---Idempotent.
---@return nil
function M.disable()
  if not enabled then
    return
  end
  enabled = false
  if hud then
    hud:unsubscribe()
  end
  pcall(vim.api.nvim_del_augroup_by_name, "ui_screenkey_resize")
  fader.cancel()
  clear()
  hud = nil
end

---Flip the HUD on/off.
---@return boolean now_enabled
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
  return enabled
end

---@return boolean
function M.is_enabled()
  return enabled
end

---The current HUD float, or `nil` while closed/disabled -- mainly for
---inspection: TESTS/screenkey_spec.lua reads its buffer directly rather than
---a bespoke peek accessor, and it's the natural hook for future
---debugging/health-check use too.
---@return Ui.Kit.Surface|nil
function M.surface()
  return surf
end

return M
