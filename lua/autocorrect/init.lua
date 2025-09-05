local M = {}

M.config = {
  auto_load_abbreviations = true,
  autocorrect_paragraph_keymap = '<Leader>d',
  source_file = nil,
  target_file = nil,
}

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  M.abbrev_file = M.config.source_file or M.get_abbreviations_path()
  M.target_file = M.config.target_file or (vim.fn.stdpath 'data' .. '/abbrev')

  M.setup_abbreviations_file()

  if M.config.auto_load_abbreviations then M.load_abbreviations() end

  if M.config.autocorrect_paragraph_keymap then
    vim.keymap.set('n', M.config.autocorrect_paragraph_keymap, function()
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

function M.setup_abbreviations_file()
  local stat = vim.uv.fs_stat(M.target_file)
  local is_symlink = stat and vim.uv.fs_readlink(M.target_file) ~= nil
  local is_regular_file = stat and not is_symlink

  if is_regular_file then return end

  if M.abbrev_file ~= M.target_file then
    local current_link = vim.uv.fs_readlink(M.target_file)
    if current_link ~= M.abbrev_file then
      if stat then vim.uv.fs_unlink(M.target_file) end

      local parent_dir = vim.fs.dirname(M.target_file)
      vim.fn.mkdir(parent_dir, 'p')

      vim.uv.fs_symlink(M.abbrev_file, M.target_file)
    end
  end
end

M.abbrev_job = nil
M.exiting = false

function M.load_abbreviations()
  local file_to_load = M.target_file
  if vim.uv.fs_stat(file_to_load) then
    M.abbrev_job = vim.fn.jobstart({ 'cat', file_to_load }, {
      on_stdout = function(_, data)
        if M.exiting then return end
        for _, line in ipairs(data) do
          if line and line ~= '' then
            local wrong, right = line:match '^(%S+)%s+(.+)$'
            if wrong and right and not M.exiting then
              vim.schedule(function()
                if not M.exiting then vim.cmd(('iabbrev %s %s'):format(wrong, right)) end
              end)
            end
          end
        end
      end,
      stdout_buffered = false,
    })

    vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimLeave', 'ExitPre' }, {
      callback = function()
        M.exiting = true
        if M.abbrev_job then vim.fn.jobstop(M.abbrev_job) end
      end,
    })
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
    vim.cmd 'belowright sbuffer __Autocorrect__'
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
      vim.fn.writefile({ wrong .. ' ' .. right }, M.target_file, 'a')
    end
  end

  vim.cmd 'close'
  vim.cmd 'wincmd _ | normal! }zz'
end

return M
