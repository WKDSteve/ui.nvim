# Screenkey — the keystroke HUD and its key capture

`ui.screenkey` shows the keys pressed in Neovim in a small corner float, for recording demos
(`:UI screenkey` toggles it, [BINDINGS.md](BINDINGS.md); what it hides is in [scope.md](scope.md)).
The capture behind it is public: another display can receive the same keys, formatted the
same way, without a second `vim.on_key()` hook of its own. The keycast overlay of
[mdview.nvim](https://github.com/WKDSteve/mdview.nvim) (the keys in the browser preview) is
such a consumer.

## `require("ui.screenkey").subscribe(callback, opts)`

```lua
local ok, screenkey = pcall(require, "ui.screenkey")
if not ok then
  return -- ui.nvim is not installed: no keys
end

local sub = screenkey.subscribe(function(entry, s)
  -- entry: the key just pressed (or counted up): { key = "<C-W>", label = "<C-W>", count = 1 }
  -- s:text(40): the recent keys as one line of at most 40 columns, as the HUD shows them
  show_somewhere(s:text(40))
end, { scope = "normal" })

-- later, when the display goes away:
sub:unsubscribe()
```

| Field | Meaning |
| --- | --- |
| `entry.key` | the `vim.fn.keytrans()` name: `j`, `<Esc>`, `<C-W>`, `<CR>` |
| `entry.label` | what to show: the `setup({ labels })` replacement of `key`, else `key` |
| `entry.count` | how many times in a row it was pressed: the same key again counts up instead of adding an entry |

`opts`:

| Option | Default | Meaning |
| --- | --- | --- |
| `scope` | `"insert_protected"` | which keys the subscription gets, see below |
| `max_entries` | `setup({ max_entries })` (30), read live | how many entries `sub:entries()` keeps; the oldest go first |

The scopes:

| Scope | Gets |
| --- | --- |
| `"normal"` | the keys typed outside Insert, Replace and Terminal mode: Normal, Visual, Operator-pending and the command line (`:w<CR>`). The key that enters Insert mode (`i`) is in, the text typed there and the `<Esc>` that leaves it are not. Never a protected key |
| `"insert_protected"` | every mode, but never a protected key. What the HUD itself shows |
| `"all"` | every key, protected ones too. For a display only the person at the keyboard sees |

A **protected** key is one typed into a secret `ui.kit` prompt or sheet (`ui.kit.surface.is_secret`),
while `vim.fn.input()` or `vim.fn.inputsecret()` waits (command-line type `@` / `-`), into a
`buftype=prompt` buffer, or into a buffer whose `'buftype'` or `'filetype'` is in
`setup({ hide = { buftypes = {...}, filetypes = {...} } })`. Whether a key is protected is
decided when it is pressed, so the `<CR>` that submits a prompt is protected too, and the keys
right before and after it are not.

The handle:

| Method | Does |
| --- | --- |
| `sub:entries()` | a copy of the recorded entries, oldest first |
| `sub:text(width)` | the entries as one line of at most `width` display columns: labels, `key×N` for repeats, `join_chars` runs; the oldest are dropped first |
| `sub:clear()` | forget the recorded entries (a fade-out does this) |
| `sub:unsubscribe()` | stop; idempotent |
| `sub:active()` | whether it still receives keys |

The callback runs on the main loop (`vim.schedule`) after every accepted key. A callback that
raises is unsubscribed and a warning is shown once, so a broken consumer cannot cost a message
per keystroke. `vim.on_key()` is attached while there is at least one subscription (the HUD's
own included) and detached with the last one: nobody listening costs nothing per key.
`require("ui.screenkey").subscriber_count()` says how many there are.

Not covered (as for the HUD): keys read with `getchar()`/`getcharstr()`, and text typed into a
`:terminal` buffer in the `insert_protected` scope (add `hide = { buftypes = { "terminal" } }`;
`normal` leaves Terminal mode out anyway).
