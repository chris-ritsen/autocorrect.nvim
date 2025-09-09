# autocorrect.nvim

Neovim port of [vim-autocorrect](https://github.com/chris-ritsen/vim-autocorrect).

## Installation and Setup

### Minimal setup

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    local autocorrect = require("autocorrect")
    autocorrect.setup()

    vim.keymap.set('n', '<leader>d', autocorrect.autocorrect_paragraph, { desc = 'Autocorrect paragraph' })
  end,
}
```

### Configuration options

The plugin adds all abbreviations in the background in batches,
which blocks UI slightly once at startup. I've created a
[patch](https://github.com/chris-ritsen/neovim/tree/keymap-bulk-insert)
for neovim that loads all of the abbreviations instantly.

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    local autocorrect = require("autocorrect")
    autocorrect.setup({
      auto_load_abbreviations = true,
      batch_size = 250,
    })

    vim.keymap.set('n', '<leader>d', autocorrect.autocorrect_paragraph, { desc = 'Autocorrect paragraph' })
  end,
}
```

### Manual loading only

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    require("autocorrect").setup({
      auto_load_abbreviations = false,
    })
  end,
}
```

## Usage

By default, the plugin's abbreviation list is symlinked to
`~/.local/share/nvim/abbrev`. If you're using a custom file, symlinking is
automatically skipped.

### Autocorrect workflow

1. Position your cursor in a paragraph with spelling errors
2. Press `<leader>d` to open the autocorrect window
3. The window shows misspelled words with suggested corrections
4. Edit corrections as needed (words marked `<correction>` need manual input)
5. Press `<Enter>` to apply all corrections and add them as abbreviations
6. Press `q` to close without applying

### Manual commands

If you have `auto_load_abbreviations = false`, you can manually load the abbreviations using:

```vim
lua require('autocorrect').load_abbreviations()
```

Reload abbreviations:

```vim
lua require('autocorrect').reload_abbreviations()
```

Check plugin health:

```vim
checkhealth autocorrect
```
