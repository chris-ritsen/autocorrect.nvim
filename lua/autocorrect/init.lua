local M = {}

M.config = {
  auto_load_abbreviations = true,
  autocorrect_paragraph_keymap = '<Leader>d',
  source_file = nil,
  target_file = nil,
  log_level = 'info', -- 'debug', 'info', 'warn', 'error'
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

M.exiting = false
M.stats = {
  load_start_time = nil,
  load_end_time = nil,
  abbreviations_loaded = 0,
  file_loaded_from = nil,
  logs = {},
  failed_abbreviations = {},
  duplicates = {},
}

local log_levels = { debug = 0, info = 1, warn = 2, error = 3 }

local function log(level, msg)
  local config_level = log_levels[M.config.log_level] or 1

  if log_levels[level] >= config_level then
    local timestamp = os.date '%H:%M:%S'
    table.insert(M.stats.logs, { level = level, msg = msg, timestamp = timestamp })
    if #M.stats.logs > 50 then table.remove(M.stats.logs, 1) end
  end
end

local function process_line(line, seen)
  if not line or line == '' then return end

  local space_pos = line:find ' '
  if not space_pos then
    table.insert(M.stats.failed_abbreviations, { line = line, error = 'Failed to parse line' })
    return
  end

  local wrong = line:sub(1, space_pos - 1)
  local right = line:sub(space_pos + 1)
  if wrong == '' or right == '' then
    table.insert(M.stats.failed_abbreviations, { line = line, error = 'Failed to parse line' })
    return
  end

  if seen[wrong] then
    table.insert(M.stats.duplicates, { line = line, original = seen[wrong] })
    return
  end

  seen[wrong] = line
  vim.cmd(('iabbrev %s %s'):format(wrong, right))
  M.stats.abbreviations_loaded = M.stats.abbreviations_loaded + 1
end

local function log_completion()
  M.stats.load_end_time = vim.uv.hrtime()
  local duration = (M.stats.load_end_time - M.stats.load_start_time) / 1000000
  local final_count = M.get_abbrev_count()
  log('info', string.format('Loaded %d abbreviations in %.2fms', M.stats.abbreviations_loaded, duration))
  log('info', string.format('Final active count: %d', final_count))
  if #M.stats.duplicates > 0 then
    log('warn', string.format('Skipped %d duplicate abbreviations', #M.stats.duplicates))
  end
  if #M.stats.failed_abbreviations > 0 then
    log('warn', string.format('%d abbreviations failed to load', #M.stats.failed_abbreviations))
  end
end

local function process_abbreviations(lines)
  M.stats.load_start_time = vim.uv.hrtime()
  local non_empty_lines = #vim.tbl_filter(function(line) return line and line ~= '' end, lines)
  log('info', 'Starting to load ' .. non_empty_lines .. ' abbreviation entries')

  vim.schedule(function()
    local seen = {}
    local batch_size = 250
    local index = 1
    local loading = false
    local augroup = vim.api.nvim_create_augroup('autocorrect_batch', { clear = true })

    local function stop_loading() loading = false end

    local function process_batch()
      if M.exiting or index > #lines or not loading then return end

      local end_index = math.min(index + batch_size - 1, #lines)

      for i = index, end_index do
        process_line(lines[i], seen)
        if not loading then return end
      end

      index = end_index + 1

      if index <= #lines then
        vim.defer_fn(process_batch, 0)
      else
        log_completion()
      end
    end

    local function start_loading()
      if not loading and index <= #lines then
        loading = true
        process_batch()
      end
    end

    vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
      group = augroup,
      callback = start_loading,
    })

    vim.api.nvim_create_autocmd(
      { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'TextChanged', 'TextChangedI', 'CmdlineChanged' },
      {
        group = augroup,
        callback = stop_loading,
      }
    )

    start_loading()
  end)
end

local function read_file_async(file_path, callback)
  log('info', 'Loading abbreviations from: ' .. file_path)
  M.stats.file_loaded_from = file_path

  vim.uv.fs_stat(file_path, function(err, stat)
    if err or not stat then
      log('error', 'Failed to stat file: ' .. (err or 'unknown error'))
      return
    end

    vim.uv.fs_open(file_path, 'r', 438, function(err, fd)
      if err or not fd then
        log('error', 'Failed to open file: ' .. (err or 'unknown error'))
        return
      end

      vim.uv.fs_read(fd, stat.size, 0, function(err, data)
        vim.uv.fs_close(fd)
        if err or not data then
          log('error', 'Failed to read file: ' .. (err or 'unknown error'))
          return
        end
        callback(vim.split(data, '\n'))
      end)
    end)
  end)
end

function M.load_abbreviations()
  vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimLeave', 'ExitPre' }, {
    callback = function() M.exiting = true end,
  })

  vim.api.nvim_create_autocmd('CursorHold', {
    once = true,
    callback = function()
      if M.exiting then return end
      read_file_async(M.target_file, process_abbreviations)
    end,
  })
end

function M.clear_abbreviations()
  vim.cmd 'iabclear'
  M.stats.abbreviations_loaded = 0
  log('info', 'Cleared all abbreviations')
end

function M.reload_abbreviations()
  log('info', 'Reloading abbreviations')
  M.clear_abbreviations()
  read_file_async(M.target_file, process_abbreviations)
end

function M.get_abbrev_count()
  local output = vim.fn.execute 'iabbrev'
  if output:match 'No abbreviations' or output:match '^%s*$' then return 0 end
  local lines = vim.split(output, '\n')

  return #vim.tbl_filter(
    function(line) return line:match '^%S+%s+' and not line:match '^Name' and not line:match '^%-%-' end,
    lines
  )
end

function M.show_stats()
  local actual_count = M.get_abbrev_count()
  local stats = {
    'Autocorrect Statistics:',
    '  File: ' .. (M.stats.file_loaded_from or 'none'),
    '  Abbreviations loaded: ' .. M.stats.abbreviations_loaded,
    '  Actual abbreviations active: ' .. actual_count,
  }

  if M.stats.load_start_time and M.stats.load_end_time then
    local duration = (M.stats.load_end_time - M.stats.load_start_time) / 1000000
    table.insert(stats, '  Load time: ' .. string.format('%.2fms', duration))
  end

  vim.notify(table.concat(stats, '\n'), vim.log.levels.INFO)
end

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
