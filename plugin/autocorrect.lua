if vim.g.loaded_autocorrect then return end

vim.g.loaded_autocorrect = 1

vim.api.nvim_create_user_command(
  'AutocorrectReload',
  function() require('autocorrect').reload_abbreviations() end,
  { desc = 'Reload abbreviations from file' }
)

vim.api.nvim_create_user_command(
  'AutocorrectClear',
  function() require('autocorrect').clear_abbreviations() end,
  { desc = 'Clear all abbreviations' }
)
