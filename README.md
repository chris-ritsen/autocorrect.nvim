# autocorrect.nvim

Neovim port of [vim-autocorrect](https://github.com/chris-ritsen/vim-autocorrect).

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "chris-ritsen/autocorrect.nvim",
  config = function()
    require("autocorrect").setup()
  end,
}
```

## Setup

```lua
require("autocorrect").setup()
```

## Usage

The autocorrection list is symlinked to `~/.local/share/nvim/abbrev`.

Press `<leader>d` with the cursor over a paragraph with typos to open a window
with all of the incorrectly spelled words. The typo will be on the left side
with a suggested correction on the right side. Delete lines and/or edit
the corrections and then press enter to save them to the abbrev file.
