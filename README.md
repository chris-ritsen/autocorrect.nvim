# autocorrect.nvim

Neovim port of [vim-autocorrect](https://github.com/chris-ritsen/vim-autocorrect).

## Description

This is a neovim plugin for an autocorrect feature built on the `iabbrev` and
`spellsuggest` commands and years worth of spelling mistakes and typos made on
qwerty keyboards.

The result is useful for writing general prose or code, but is especially good
for a stream-of-consciousness or for transcription. It's fast and accurate
enough to consider using unconditionally every time neovim is started.

The goal is to create the largest list of typos and spelling mistakes with
opinionated corrections that exists, without compromising accuracy and without
ever doing anything unexpected.

It's not possible to fix everything all the time, but if used correctly, many
typos will be seen once and never again.

The full list of typos is in [abbrev](abbrev). The words in the included list
were generated from various sources, such as personal notes, fiction,
non-fiction, and while writing code. It is made up of only lines like these:

```
teh the
```

These are then added to neovim as iabbrev definitions:

```vim
iabbrev teh the
```

It's not a grammar checker. There's no way to fix transposition typos on
short words like `from`/`form`, but it works well for longer words or those
that are difficult to spell.

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

### Git Hook Setup

To automatically sort and deduplicate the `abbrev` file on commit, install the pre-commit hook:

```bash
GIT_DIR=$(git rev-parse --git-dir)
cp hooks/pre-commit "$GIT_DIR/hooks/pre-commit"
chmod +x "$GIT_DIR/hooks/pre-commit"
```

This ensures the `abbrev` file stays sorted using `LC_ALL=C sort -u`, matching Neovim's `:sort u` behavior.

### Autocorrect workflow

1. Position your cursor in a paragraph with spelling errors
2. Press `<leader>d` to open the autocorrect window
3. The window shows misspelled words with suggested corrections
4. Edit corrections as needed (words marked `<correction>` need manual input)
5. Press `<Enter>` or `<c-j>` to apply all corrections and add them as abbreviations
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

### Disabling autocorrect

```vim
iabclear
```

### Workflow while writing

If you need to write a word that would otherwise be autocorrected, such as
`teh`, type `<C-C>` or `<C-V>` after writing the word. `<C-C>` goes back to
normal mode without performing the correction, while `<C-V>` stays in insert
mode.

Some tips for writing prose with this:

- Add words to the good word list with `zg` to avoid accidentally correcting
  them.
- Don't assume that `spellsuggest` is going to suggest the correct word.
- If a word is likely to have been typed badly, type it again at least once
  more. Unless editing is done soon after, the correct word may not be
  obvious.
- If a word starts off badly, either delete it or add a space and type it
  again. Typos with unrelated prefixes are not as useful and are easily
  avoided.
- Review recently added typos and check for errors. Hastily adding
  corrections isn't reliable.

## About the list

I've been building this list since 2012. This list exists for my own benefit,
so I'm not interested in contributions. Reasonable suggestions will be
considered. I write in the `en-US` locale with a standard qwerty layout. It
was created on the following keyboards:

- Apple US English keyboards
- [HHKB Pro JP](https://hhkb.io/models/HHKB_Professional_JP/)
- [HHKB Professional 2](https://hhkb.io/models/HHKB_Professional_2/)

Deleting the words in [abbrev](abbrev) and starting from
scratch with any set of rules is an option, but the included list was created
by making every effort to avoid unintentional corrections. Typos will be
pruned from this list regularly. This list contains obvious errors (i.e.,
correcting a word to a misspelling, or going against the listed rules).

Only one correction can exist for any given typo, so sometimes a decision must
be made to prioritize different types of typing mistakes. There are several
apparent categories of typos in this list. The main ones are:

- Extraneous or missing characters due to sloppy typing (`Henfdrix`/`Hendrix`
  and (`accont`/`account`). This includes extreme laziness
  (`Cahrtaxccteristics`/`Characteristics`).
- Omission of diacritical marks (correct `Patisambhida`/`Paṭisambhidā` and
  `Cliche`/`Cliché` but not `resume`/`résumé`).
- Repeated characters due to a high network latency or high key repeat rate
  (`Whaaaat`/`What`).
- Spelling mistakes, including a refusal to learn to correctly spell a word or
  guesses (`compatability`/`compatibility`) (`anurism`/`aneurysm`).
- Timing errors with the shift keys (`INform`/`Inform`).
- Timing errors with the spacebar (`atht`/`at` and `costsa`/`costs`).
- Transposition of characters due to timing errors between hands or fingers
  (`thta`/`that`).
- Wrong key pressed (`Hpw`/`How`).

Numbers are almost always considered to be extraneous characters by this list,
especially when within a word (`However3`/`However` and `z3est`/`zest`).

Timing errors are common when shift is used for capitalization
(`ONly`/`Only`). Transposition of characters is usually due to individual
fingers pressing keys at the wrong time while trying to coordinate both hands
as quickly as possible.

Timing errors with the spacebar are also common. The typo `yto` could be the
word `toy`, but it's extremely unlikely. It was actually a stray letter from
a previous word prefixed to the word `to`. To typo the word `toy` as `yto`
requires pressing the keys in a reversed order with one hand and is not simply
a timing error between hands. While possible, that type of error almost never
happens in practice.

### Rules for the list

#### General

- Avoid adding short typos or words, such as those under four characters long.
- Avoid making decisions about mixed-case acronyms.
- Don't add any symbols to the correction. `DBus` should not correct to
  `D-Bus`.
- Don't add contractions or word fragments. `hadn` shouldn't correct to
  `hand` and no entry should exist for `shouldn` or `couldn`. No corrections
  like `couldnt`/`couldn't` or `dont`/`don't` should be added. It's not
  likely to be handled correctly by the script that adds abbreviations,
  either.
- Don't add words that are unlikely to broadly usable, such as camel case
  variable names. Correcting `EventEMitter`, to `EventEmitter` is fine.
- Don't consider foreign words as typos, if known.
- Don't correct common abbreviations—such as `acct` for `account`—even if it
  happened to be a typo for `act`.
- Prioritize compatibility with writing prose over code, but attempt to make
  it work with both if possible.
- Remove any autocorrection that results in a word that was unintended.
- Remove any typos that end up being programs, libraries, variables, names,
  nouns, brands, etc., but only when discovered. For example, the program
  named `mosquitto` should not be corrected to `mosquito` and `msoquitto`
  should be corrected to `mosquitto`, not `mosquito`.

#### Spelling mistakes

- Avoid changing capitalization of words, as it could be part of a string
  literal or variable name. `Paypal` should not be changed into `PayPal`, but
  `LaTex` correcting to `LaTeX` is fine. The word `I` should not corrected
  when `i` is typed. Mistakes with shift key timing are only considered for
  the first two characters.
- Don't attempt to localize/localise words.
- Don't enforce a preferred spelling, even for archaic words. `Eery` should
  not be corrected to `Eerie`.

#### Typing mistakes

- Don't correct short words with a missing letter.
- Don't use this for expanding abbreviated words. At most, this should be
  limited to a character or two omitted from the end of a long word, or a
  short word if the correct word is unambiguous. Correcting `abou` to `about`
  is fine.
- Don't change the tense of words. Be explicit about it if possible.
- Generally, don't pluralize words that weren't already pluralized. While
  `keyboaresd` is obviously a transposition typo for `keyboards`, it's
  corrected to `keyboard` instead. Type an explicit `s` at the end of a badly
  typed word to ensure the correction will also have an `s` at the end. In
  practice, this looks like `Effecsts`/`Effects`. This rule only applies to
  pluralization, so `suppooes` would be corrected to `suppose`. `COntorsl`
  should still be corrected to `Controls`, as this is due to mistimed hands,
  not fingers on the same hand.
- No synthetic typos.
- Remove any leading characters from the previous word due to a mistimed
  spacebar press, unless they are valid words or used as variable names. The
  typo `atht` made by typing `at that` with a mistimed spacebar should not be
  corrected into `at` or `that`.
