# autocorrect.nvim

Neovim port of [vim-autocorrect](https://github.com/chris-ritsen/vim-autocorrect).

## Installation and Setup

### Default config

The plugin adds all abbreviations in the background in batches,
which blocks UI slightly once at startup. I've created a
[patch](https://github.com/chris-ritsen/neovim/tree/load-abbrev-from-file-at-startup)
for neovim that loads all of the abbreviations instantly.

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    require("autocorrect").setup({
      auto_load_abbreviations = true,
      autocorrect_paragraph_keymap = '<Leader>d',
    })
  end,
}
```

### Minimal config (no automatic loading or keymappings)

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    require("autocorrect").setup({
      auto_load_abbreviations = false,
      autocorrect_paragraph_keymap = nil,
    })
  end,
}
```

## Usage

By default, the plugin's abbreviation list is symlinked to
`~/.local/share/nvim/abbrev`. If you're using a custom file, symlinking is
automatically skipped.

If you have `auto_load_abbreviations = false`, you can manually load the abbreviations using:

```
lua require('autocorrect').load_abbreviations()
```

Press `<leader>d` (or your configured keymap) with the cursor over a paragraph
with typos to open a window with all of the incorrectly spelled words. The
typo will be on the left side with a suggested correction on the right side.
Delete lines and/or edit the corrections and then press enter to save them to
the abbreviation file.
