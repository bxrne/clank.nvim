# clank.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/bxrne/clank.nvim/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

clank.nvim wires AI coding "harnesses" (Claude Code, with more planned) into
Neovim through a small provider abstraction, so you can send a visual
selection to the model and have the result applied directly to your buffer
(reversible with normal `u` undo).

## Requirements

- Neovim >= 0.10
- The `claude` CLI on your `$PATH` (for the default `claude` harness)

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

## Configuration

| Option           | Type            | Default       | Description                                  |
| ----------------- | --------------- | -------------- | --------------------------------------------- |
| `harness`         | `string`        | `"claude"`     | Provider used to handle requests             |
| `model`           | `string`        | `"sonnet-4.6"` | Model passed to the harness                  |
| `keymaps.fill`    | `string\|false` | `"<leader>af"` | Visual-mode keymap for `:ClankFill`, `false` to disable |

## Providers

Providers are registered against `lua/clank/provider/init.lua`'s registry and
implement a `send(opts, callbacks)` contract:

```lua
-- opts: { prompt, system?, session_id?, cwd }
-- callbacks: { on_chunk(text), on_done(result), on_error(err) }
-- returns a handle with handle.cancel()
```

The built-in `claude` provider shells out to the `claude` CLI in headless
mode (`claude -p ... --output-format text`). Additional harnesses (Codex,
opencode, etc.) can be added by implementing the same contract and
registering under a new name.

## Development

```sh
make test
```

Tests run via [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) +
busted. The `claude` provider's tests stub `vim.system`, so no real CLI
invocation or network access is required.
