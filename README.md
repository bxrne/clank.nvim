# clank.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/bxrne/clank.nvim/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

**Never leave Neovim for AI or GitHub again.**

Surgical AI fills, steppable code review, and full pull-request workflows —
checkout, comment, approve — without touching a browser or a second
terminal. clank.nvim doesn't invent new UI to hold any of this: issues land
in your quickfix list, edits land in your buffers, every change is undoable
with a plain `u`, and PRs live in real `git worktree`s you navigate like any
other project. It's all Neovim you already know, pointed at an AI harness of
your choice.

- **Sniper-precision fills** — highlight exactly what needs writing, `:ClankFill`
  it, keep going. No chat window, no copy-paste.
- **Steppable review** — `:ClankReview` turns a diff (uncommitted, a commit, or
  a range) into quickfix entries you walk with `]q`/`[q`, then `:ClankFix`
  knocks them out.
- **Free-form agent tasks** — `:ClankDo` describes what you want in English;
  the harness explores the repo and comes back with a reviewable plan of
  Neovim actions, not an unsupervised script.
- **GitHub-native PR housekeeping** — `:ClankPR {n}` checks a pull request out
  into its own worktree (any status: open, closed, merged) and pulls existing
  review comments straight into the quickfix list. `:ClankPRComment` drafts
  replies inline; `:ClankPRSubmit` ships them as a real approve/request-changes/comment
  review — no browser tab required.
- **Bring your own harness** — Claude Code and opencode ship built in, behind a
  small provider contract, with more on the way. Nothing here is locked to one
  vendor.

## Requirements

- Neovim >= 0.10
- The `claude` CLI on your `$PATH` (for the default `claude` harness), or the
  `opencode` CLI (for the `opencode` harness)
- The `gh` CLI, authenticated, for `:ClankPR`/`:ClankPRComment`/`:ClankPRSubmit`

## Installation

With `vim.pack` (Neovim >= 0.12):

```lua
vim.pack.add({
  "https://github.com/bxrne/clank.nvim",
})

require("clank").setup()
```

With `lazy.nvim`:

```lua
{
  "bxrne/clank.nvim",
  opts = {},
}
```

## Setup

```lua
require("clank").setup({
  harness = "claude",   -- which provider to dispatch to
  model = "sonnet-4.6",
  keymaps = {
    fill = "<leader>af", -- visual-mode keymap, set to false to disable
  },
})
```

## Commands

### `:ClankFill`

Send the current visual selection to the configured harness, asking it to
fill in / complete the selected code, and replace the selection with the
response. Also bound to the `keymaps.fill` keymap (default `<leader>af`) in
visual mode.

Usage: select a block (e.g. an empty function body) in visual mode, then
press `<leader>af` (or run `:ClankFill`).

### `:ClankReview {n}`

Send a git diff to the configured harness for review and load its comments
into the quickfix list. Requires `git` to be on `$PATH` and the current
working directory to be inside a git repository.

The required integer argument selects what to review:

- `0` — uncommitted changes (staged and unstaged)
- `1` — the most recent commit
- `2` — the commit before that
- ...and so on

The harness is asked to respond with one `path:line: message` line per
issue, which is parsed straight into the quickfix list (`:copen` to view).

Usage: `:ClankReview 0` to review your working tree changes, `:ClankReview 1`
to review the last commit, etc.

### `:ClankFix`

Send the buffers referenced by the quickfix list to the configured harness,
asking it to fix the listed issues, and replace each buffer's contents with
the response.

Run `:ClankFix` with no range to fix every entry in the quickfix list.
Alternatively, from the quickfix window (`:copen`), select a range of lines
in visual mode and run `:'<,'>ClankFix` to fix only those entries.

### `:ClankDo {prompt}`

Give the configured harness a free-form task in natural language. The harness
explores the repository as needed and responds with a structured plan of
Neovim actions, which clank then executes for you. Because the default
`claude` harness is agentic, it can read files and run git while deciding what
to do.

```
:ClankDo review all the hotspots and add them to my quickfix list
:ClankDo rename the Config type to ClankConfig everywhere
:ClankDo open a vertical split with the busiest source file
```

The harness must reply with a JSON object, `{ "actions": [ ... ] }`, where each
action is one of:

- `{ "type": "command", "command": "<ex command>" }` — run an Ex command
  (e.g. `copen`, `vsplit foo.lua`).
- `{ "type": "qflist", "action": "r"|"a", "items": [...] }` — replace (`r`) or
  append (`a`) quickfix items (`{ filename, lnum, text }`).
- `{ "type": "edit", "path": "<path>", "content": "<full new contents>" }` —
  overwrite a file's buffer with new contents (reversible with `u`).

Before anything runs, clank shows the plan and asks for confirmation. Set
`agent.confirm = false` to apply plans without prompting.

### `:ClankPR {n}`

Check out pull request `n` into its own `git worktree` (a sibling directory
named `<repo>-pr-{n}`, on a local branch `clank-pr-{n}`) and switch Neovim's
current tab into it (`:tcd`), so you can navigate and edit the PR's files
without disturbing your main working tree. Requires `git` and the `gh` CLI on
`$PATH`, authenticated against the repo's remote.

Because PR head refs (`pull/{n}/head`) live on GitHub indefinitely, this works
for open, closed, and merged PRs alike — handy for going back to review or
re-read an old one.

Re-running `:ClankPR {n}` when the worktree already exists just `:tcd`s back
into it instead of re-fetching.

Existing line-anchored review comments on the PR are pulled in automatically
and loaded into the quickfix list (`:copen` to browse), so you can jump
straight to what reviewers already flagged.

Usage: `:ClankPR 123` to open PR #123 in a worktree.

### `:ClankPRComment`

With the cursor on a line inside a `:ClankPR` worktree, opens a small floating
buffer to draft a review comment on that line. Press `<CR>` in normal mode to
queue it, or `q`/`<Esc>` to cancel. Comments are queued locally per-PR and are
not sent to GitHub until you run `:ClankPRSubmit` — draft as many as you like
across as many files as you like first.

### `:ClankPRSubmit`

Submits everything queued with `:ClankPRComment` as a single GitHub PR
review. Prompts (via `vim.ui.select`) for a verdict — Approve, Request
changes, or Comment — then (via `vim.ui.input`) for an optional overall
summary, and posts the review in one request. A summary is required if you
pick anything other than Approve with no comments queued. Works on PRs of any
status (open, closed, or merged) since GitHub allows reviewing those too.
Clears the local queue on success.

## Configuration

| Option           | Type            | Default       | Description                                  |
| ----------------- | --------------- | -------------- | --------------------------------------------- |
| `harness`         | `string`        | `"claude"`     | Provider used to handle requests             |
| `model`           | `string`        | `"sonnet-4.6"` | Model passed to the harness                  |
| `keymaps.fill`    | `string\|false` | `"<leader>af"` | Visual-mode keymap for `:ClankFill`, `false` to disable |
| `agent.confirm`   | `boolean`       | `true`         | Confirm before running a `:ClankDo` action plan |

## Providers

Providers are registered against `lua/clank/provider/init.lua`'s registry and
implement a `send(opts, callbacks)` contract:

```lua
-- opts: { prompt, system?, session_id?, cwd }
-- callbacks: { on_chunk(text), on_done(result), on_error(err) }
-- returns a handle with handle.cancel()
```

The built-in `claude` provider shells out to the `claude` CLI in headless
mode (`claude -p ... --output-format text`). The built-in `opencode` provider
shells out to `opencode run ...`; its models are addressed as `provider/model`
(e.g. `anthropic/claude-sonnet-4-5`), and any `provider/model` string is
accepted. Additional harnesses (Codex, etc.) can be added by implementing the
same contract and registering under a new name.

To use opencode:

```lua
require("clank").setup({
  harness = "opencode",
  model = "anthropic/claude-sonnet-4-5",
})
```

## Development

```sh
make test
```

Tests run via [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) +
busted. The `claude` provider's tests stub `vim.system`, so no real CLI
invocation or network access is required.
