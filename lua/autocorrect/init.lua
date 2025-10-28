local M = {}

M.begin_line = nil
M.end_line = nil
M.exiting = false
M.last_buf = nil

M.stats = {
  abbreviations_loaded = 0,
  duplicates = {},
  failed_abbreviations = {},
  file_loaded_from = nil,
  load_end_time = nil,
  load_start_time = nil,
  logs = {},
  loading_method = nil,
  load_timing = nil,
}

M.config = {
  auto_load_abbreviations = true,
  batch_size = 250,
  log_level = 'debug', -- 'debug', 'info', 'warn', 'error'
  source_file = nil,
  target_file = nil,
}

local log_levels = {
  debug = 0,
  error = 3,
  info = 1,
  warn = 2,
}

local function log(level, msg)
  local config_level = log_levels[M.config.log_level] or 1

  if log_levels[level] >= config_level then
    local timestamp = os.date '%H:%M:%S'
    table.insert(M.stats.logs, { level = level, msg = msg, timestamp = timestamp })
    if #M.stats.logs > 50 then table.remove(M.stats.logs, 1) end
  end
end

local function elapsed_ms(start, stop) return (stop - start) / 1e6 end

local function parse_line(line, seen)
  if not line or line == '' then return nil end

  local space_pos = line:find ' '
  if not space_pos or space_pos == 1 or space_pos == #line then
    table.insert(M.stats.failed_abbreviations, { line = line, error = 'Failed to parse line' })
    return nil
  end

  local wrong = line:sub(1, space_pos - 1)
  local right = line:sub(space_pos + 1)

  if seen and seen[wrong] then
    table.insert(M.stats.duplicates, { line = line, original = seen[wrong] })
    return nil
  end

  if seen then seen[wrong] = line end
  return wrong, right
end

local function define_abbrev(lhs, rhs)
  vim.cmd(('iabbrev %s %s'):format(lhs, rhs))
  M.stats.abbreviations_loaded = M.stats.abbreviations_loaded + 1
end

-- Setup

function M.setup(opts)
  opts = opts or {}

  M.config = vim.tbl_deep_extend('force', M.config, opts)
  M.abbrev_file = M.config.source_file or M.get_abbreviations_path()
  M.target_file = M.config.target_file or (vim.fn.stdpath 'data' .. '/abbrev')
  M.setup_abbreviations_file()

  if M.config.auto_load_abbreviations then M.load_abbreviations() end
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

-- Lifecycle

local function process_abbreviations(lines)
  local processing_start_time = vim.uv.hrtime()

  local filter_start = vim.uv.hrtime()
  local non_empty_lines = #vim.tbl_filter(function(line) return line and line ~= '' end, lines)
  local filter_end = vim.uv.hrtime()
  log('debug', string.format('Filter took %.2fms for %d lines', elapsed_ms(filter_start, filter_end), #lines))

  if non_empty_lines > 0 then
    local lhs_array = {}
    local rhs_array = {}
    local seen = {}
    local count = 0
    local parsing_start = vim.uv.hrtime()

    for _, line in ipairs(lines) do
      local wrong, right = parse_line(line, seen)

      if wrong and right then
        count = count + 1
        lhs_array[count] = wrong
        rhs_array[count] = right
      end
    end

    local parsing_end = vim.uv.hrtime()

    log(
      'debug',
      string.format('Parsing took %.2fms, found %d valid abbreviations', elapsed_ms(parsing_start, parsing_end), count)
    )

    if #lhs_array > 0 then
      local start_time = vim.uv.hrtime()
      local success = pcall(vim.api.nvim_set_keymap, 'ia', lhs_array, rhs_array, {})

      if success then
        local end_time = vim.uv.hrtime()
        M.stats.abbreviations_loaded = #lhs_array
        M.stats.loading_method = 'Bulk API'
        M.stats.load_end_time = end_time
        M.stats.load_timing = elapsed_ms(start_time, end_time)

        log('info', string.format('API loaded %d abbreviations in %.2fms', #lhs_array, M.stats.load_timing))

        local total_duration = elapsed_ms(processing_start_time, M.stats.load_end_time)
        log('info', string.format('Total processing time: %.2fms', total_duration))
        return
      else
        log('info', 'Bulk API failed, falling back to async individual commands')
        local reconstructed_lines = {}

        for i = 1, #lhs_array do
          reconstructed_lines[i] = lhs_array[i] .. ' ' .. rhs_array[i]
        end

        M.stats.loading_method = 'iabbrev commands'
        log('info', 'Starting async load of ' .. #reconstructed_lines .. ' abbreviation entries')

        local batch_size = M.config.batch_size
        local index = 1

        local function process_next_batch()
          if M.exiting or index > #reconstructed_lines then
            M.stats.load_end_time = vim.uv.hrtime()
            local duration = elapsed_ms(M.stats.load_start_time, M.stats.load_end_time)

            log(
              'info',
              string.format('Async loaded %d abbreviations in %.2fms', M.stats.abbreviations_loaded, duration)
            )

            return
          end

          local end_index = math.min(index + batch_size - 1, #reconstructed_lines)

          for i = index, end_index do
            local wrong, right = parse_line(reconstructed_lines[i], nil)
            if wrong and right then define_abbrev(wrong, right) end
          end

          index = end_index + 1
          vim.defer_fn(process_next_batch, 1)
        end

        vim.defer_fn(process_next_batch, 0)
        return
      end
    end
  end

  M.stats.loading_method = 'iabbrev commands'
  log('info', 'Starting to load ' .. non_empty_lines .. ' abbreviation entries using iabbrev commands')

  local function log_completion()
    M.stats.load_end_time = vim.uv.hrtime()

    local duration = elapsed_ms(M.stats.load_start_time, M.stats.load_end_time)

    log('info', string.format('Loaded %d abbreviations in %.2fms', M.stats.abbreviations_loaded, duration))

    vim.defer_fn(function() log('info', string.format('Final active count: %d', M.get_abbrev_count())) end, 0)

    if #M.stats.duplicates > 0 then
      log('warn', string.format('Skipped %d duplicate abbreviations', #M.stats.duplicates))
    end

    if #M.stats.failed_abbreviations > 0 then
      log('warn', string.format('%d abbreviations failed to load', #M.stats.failed_abbreviations))
    end
  end

  local function process_line(line, seen)
    local wrong, right = parse_line(line, seen)
    if wrong and right then define_abbrev(wrong, right) end
  end

  vim.schedule(function()
    local seen = {}
    local batch_size = M.config.batch_size
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
        vim.schedule(process_batch)
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
      callback = start_loading,
      group = augroup,
    })

    vim.api.nvim_create_autocmd(
      { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'TextChanged', 'TextChangedI', 'CmdlineChanged' },
      {
        callback = stop_loading,
        group = augroup,
      }
    )

    start_loading()
  end)
end

local function read_file_async(file_path, callback)
  log('info', 'Loading abbreviations from: ' .. file_path)
  M.stats.file_loaded_from = file_path
  M.stats.load_start_time = vim.uv.hrtime()
  local file_start_time = M.stats.load_start_time

  vim.uv.fs_stat(file_path, function(err, stat)
    if err or not stat then
      log('error', 'Failed to stat file: ' .. (err or 'unknown error'))
      return
    end

    vim.uv.fs_open(file_path, 'r', 0, function(err, fd)
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

        local file_end_time = vim.uv.hrtime()
        local file_duration = elapsed_ms(file_start_time, file_end_time)
        log('info', string.format('File loaded in %.2fms', file_duration))

        callback(vim.split(data, '\n'))
      end)
    end)
  end)
end

function M.load_abbreviations()
  vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimLeave', 'ExitPre' }, {
    callback = function() M.exiting = true end,
  })

  local file_start = vim.uv.hrtime()
  local data = vim.fn.readfile(M.target_file)
  local file_end = vim.uv.hrtime()

  log('info', string.format('File loaded in %.2fms', elapsed_ms(file_start, file_end)))
  M.stats.file_loaded_from = M.target_file
  M.stats.load_start_time = file_start
  process_abbreviations(data)
end

function M.clear_abbreviations()
  vim.cmd 'iabclear'
  M.stats.abbreviations_loaded = 0
  log('info', 'Cleared all abbreviations')
end

function M.reload_abbreviations()
  log('info', 'Reloading abbreviations')
  M.clear_abbreviations()
  M.load_abbreviations()
end

-- Stats

function M.get_abbrev_count()
  local output = vim.fn.execute 'iabbrev'
  if output:match 'No abbreviation found' or output:match '^%s*$' then return 0 end
  local lines = vim.split(output, '\n')

  return #vim.tbl_filter(
    function(line) return line:match '^%S+%s+' and not line:match '^Name' and not line:match '^%-%-' end,
    lines
  )
end

-- Add autocorrection workflow

function M.autocorrect_paragraph()
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
end

function M.autocorrect_range(first, last)
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  local corrections = {}

  local function get_all_spell_suggestions(line)
    local suggestions = {}
    local remaining = line

    while true do
      local bad = vim.fn.spellbadword(remaining)
      local word = bad[1]
      if word == '' then break end

      if not suggestions[word] then
        local sug = vim.fn.spellsuggest(word, 20)
        local suggestion = '<correction>'

        for _, s in ipairs(sug) do
          if not s:find '%s' and not s:find "'" and not s:find '-' then
            suggestion = s
            break
          end
        end

        suggestions[word] = suggestion
      end

      local idx = remaining:find(word, 1, true)
      if not idx then break end
      remaining = remaining:sub(idx + #word)
    end

    return suggestions
  end

  for _, line in ipairs(lines) do
    for key, value in pairs(get_all_spell_suggestions(line)) do
      corrections[key] = value
    end
  end

  if vim.tbl_isempty(corrections) then return end

  M.last_buf = vim.api.nvim_get_current_buf()
  M.begin_line = first
  M.end_line = last

  local entries = {}

  for key, value in pairs(corrections) do
    table.insert(entries, key .. ' ' .. value)
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
  local namespace = vim.api.nvim_create_namespace 'autocorrect'

  for i, line in ipairs(entries) do
    local start_col, end_col = line:find('<correction>', 1, true)

    if start_col and end_col then
      vim.api.nvim_buf_add_highlight(autocorrect_buf, namespace, 'Error', i - 1, start_col - 1, end_col)
    end
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
    -- vim.cmd 'wincmd _ | normal! }zz'
  end, { buffer = autocorrect_buf, silent = true })
end

function M.commit()
  local autocorrect_buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(autocorrect_buf, 0, -1, false)

  for _, line in ipairs(lines) do
    local wrong, right = parse_line(line, nil)

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

      define_abbrev(wrong, right)
      vim.fn.writefile({ wrong .. ' ' .. right }, M.target_file, 'a')
    end
  end

  vim.cmd 'close'
  -- vim.cmd 'wincmd _ | normal! }zz'
end

return M
