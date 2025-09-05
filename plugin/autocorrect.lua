if vim.g.loaded_autocorrect then return end

vim.g.loaded_autocorrect = 1

require('autocorrect').setup()
