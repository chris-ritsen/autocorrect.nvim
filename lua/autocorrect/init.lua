local M = {}

M.config = {
  auto_load_abbreviations = true,
  keymap = '<Leader>d',
}

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  M.abbrev_file = M.get_abbreviations_path()
  M.setup_abbreviations_symlink()

  if M.config.auto_load_abbreviations then M.load_abbreviations() end

  if M.config.keymap then
    vim.keymap.set('n', M.config.keymap, function()
      local current = vim.api.nvim_win_get_cursor(0)[1]
      local start = current
      while start > 1 and vim.fn.getline(start - 1):match '^%s*$' == nil do
        start = start - 1
      end

      local stop = current
      local last_line = vim.fn.line '$'
      while stop < last_line and vim.fn.getline(stop + 1):match '^%s*$' == nil do
        stop = stop + 1
      end

      M.autocorrect_range(start, stop)
    end, { silent = true })
  end
end

function M.get_abbreviations_path()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))) .. '/abbrev'
end

function M.setup_abbreviations_symlink()
  local abbrev_file = M.abbrev_file
  local symlink_path = vim.fn.stdpath 'data' .. '/abbrev'

  local current_link = vim.uv.fs_readlink(symlink_path)
  if current_link ~= abbrev_file then
    local stat = vim.uv.fs_stat(symlink_path)
    if stat then vim.uv.fs_unlink(symlink_path) end

    vim.uv.fs_symlink(abbrev_file, symlink_path)
  end
end

function M.load_abbreviations()
  if vim.uv.fs_stat(M.abbrev_file) then
    local lines = vim.fn.readfile(M.abbrev_file)
    for _, line in ipairs(lines) do
      local wrong, right = line:match '^(%S+)%s+(.+)$'
      if wrong and right then vim.cmd(('iabbrev %s %s'):format(wrong, right)) end
    end
  end
end

function M.clear_abbreviations() vim.cmd 'iabclear' end

local function get_all_spell_suggestions(line)
  local suggestions = {}
  local remaining = line

  while true do
    local bad = vim.fn.spellbadword(remaining)
    local word = bad[1]
    if word == '' then break end

    if not suggestions[word] then
      local sug = vim.fn.spellsuggest(word, 5)
      local suggestion = (#sug > 0 and not sug[1]:find '%s') and sug[1] or '<correction>'
      suggestions[word] = suggestion
    end

    local idx = remaining:find(word, 1, true)
    if not idx then break end
    remaining = remaining:sub(idx + #word)
  end

  return suggestions
end

M.last_buf = nil
M.begin_line = nil
M.end_line = nil

function M.autocorrect_range(first, last)
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  local corrections = {}
  for _, line in ipairs(lines) do
    for k, v in pairs(get_all_spell_suggestions(line)) do
      corrections[k] = v
    end
  end

  if vim.tbl_isempty(corrections) then return end

  M.last_buf = vim.api.nvim_get_current_buf()
  M.begin_line = first
  M.end_line = last

  local entries = {}
  for k, v in pairs(corrections) do
    table.insert(entries, k .. ' ' .. v)
  end
  
  local height = math.min(15, #entries)
  
  local existing_buf = vim.fn.bufnr '__Autocorrect__'
  if existing_buf ~= -1 then
    vim.cmd('belowright sbuffer __Autocorrect__')
    vim.cmd('resize ' .. height)
    vim.bo.modifiable = true
    vim.cmd '%delete _'
  else
    vim.cmd('belowright ' .. height .. 'split __Autocorrect__')
  end

  local autocorrect_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(autocorrect_buf, 0, -1, false, entries)
  local ns = vim.api.nvim_create_namespace 'autocorrect'

  for i, line in ipairs(entries) do
    local s, e = line:find('<correction>', 1, true)
    if s and e then vim.api.nvim_buf_add_highlight(autocorrect_buf, ns, 'Error', i - 1, s - 1, e) end
  end

  vim.bo[autocorrect_buf].buftype = 'nofile'
  vim.bo[autocorrect_buf].bufhidden = 'delete'
  vim.bo[autocorrect_buf].swapfile = false
  vim.bo[autocorrect_buf].modifiable = true
  vim.wo.spell = true
  vim.wo.wrap = false
  vim.wo.winfixheight = true
  vim.bo.filetype = 'autocorrect'

  vim.keymap.set('n', '<CR>', M.commit, { buffer = autocorrect_buf, silent = true })
  vim.keymap.set('n', '<C-j>', M.commit, { buffer = autocorrect_buf, silent = true })
  vim.keymap.set('n', 'q', function()
    vim.cmd 'close'
    vim.cmd('sbuffer ' .. M.last_buf)
    vim.cmd 'wincmd _ | normal! }zz'
  end, { buffer = autocorrect_buf, silent = true })
end

function M.commit()
  local autocorrect_buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(autocorrect_buf, 0, -1, false)

  for _, line in ipairs(lines) do
    local wrong, right = line:match '^(%S+)%s+(%S+)$'
    if wrong and right then
      vim.api.nvim_buf_call(
        M.last_buf,
        function()
          vim.cmd(
            ('%d,%ds/%s/%s/ge'):format(
              M.begin_line,
              M.end_line,
              vim.fn.escape(wrong, '/\\'),
              vim.fn.escape(right, '/\\')
            )
          )
        end
      )
      vim.cmd(('iabbrev %s %s'):format(wrong, right))
      vim.fn.writefile({ wrong .. ' ' .. right }, M.abbrev_file, 'a')
    end
  end

  vim.cmd 'close'
  vim.cmd 'wincmd _ | normal! }zz'
end

return M
