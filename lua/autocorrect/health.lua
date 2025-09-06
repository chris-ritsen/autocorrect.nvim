local M = {}

function M.check()
  vim.health.start 'autocorrect.nvim'

  local autocorrect = require 'autocorrect'

  if autocorrect then
    vim.health.ok 'Plugin loaded successfully'
  else
    vim.health.error 'Plugin failed to load'
    return
  end

  local config = autocorrect.config

  if config then
    vim.health.ok 'Configuration loaded'
    vim.health.info('auto_load_abbreviations: ' .. tostring(config.auto_load_abbreviations))
    vim.health.info('batch_size: ' .. config.batch_size)
    vim.health.info('keymap: ' .. (config.autocorrect_paragraph_keymap or 'none'))
  else
    vim.health.warn 'No configuration found'
  end

  if jit then
    vim.health.ok('LuaJIT detected: ' .. jit.version)
    local ffi_ok, ffi = pcall(require, 'ffi')

    if ffi_ok then
      vim.health.ok 'FFI available'
    else
      vim.health.warn 'FFI not available'
    end
  else
    vim.health.warn 'Standard Lua detected (not LuaJIT) - using fallback method'
  end

  local target_file = autocorrect.target_file
  local source_file = autocorrect.abbrev_file

  if target_file then
    local stat = vim.uv.fs_stat(target_file)

    if stat then
      vim.health.ok('Target file exists: ' .. target_file)
      vim.health.info('File size: ' .. stat.size .. ' bytes')
    else
      vim.health.warn('Target file not found: ' .. target_file)
    end
  else
    vim.health.error 'Target file path not set'
  end

  if source_file then
    local stat = vim.uv.fs_stat(source_file)

    if stat then
      vim.health.ok('Source file exists: ' .. source_file)
      vim.health.info('File size: ' .. stat.size .. ' bytes')
    else
      vim.health.warn('Source file not found: ' .. source_file)
    end
  else
    vim.health.error 'Source file path not set'
  end

  if target_file and source_file and target_file ~= source_file then
    local link = vim.uv.fs_readlink(target_file)

    if link == source_file then
      vim.health.ok 'Symlink correctly points to source file'
    else
      vim.health.warn('Symlink issue - target: ' .. (link or 'not a symlink'))
    end
  end

  local stats = autocorrect.stats
  local actual_count = autocorrect.get_abbrev_count()

  vim.health.info('Abbreviations loaded by plugin: ' .. stats.abbreviations_loaded)
  vim.health.info('Active abbreviations in Neovim: ' .. actual_count)

  if stats.abbreviations_loaded > 0 then
    if stats.load_start_time and stats.load_end_time then
      local duration = (stats.load_end_time - stats.load_start_time) / 1000000
      vim.health.info(string.format('Load time: %.2fms', duration))
    end
  end

  if actual_count == 0 and config.auto_load_abbreviations then
    vim.health.warn 'Auto-loading is enabled but no abbreviations are active'
  elseif actual_count == 0 then
    vim.health.info 'No abbreviations loaded (auto-loading disabled)'
  end

  if #stats.duplicates > 0 then
    vim.health.warn(#stats.duplicates .. ' duplicate abbreviations skipped:')

    for _, dup in ipairs(stats.duplicates) do
      vim.health.info('  ' .. dup.line .. ' (original: ' .. dup.original .. ')')
    end
  end

  if #stats.failed_abbreviations > 0 then
    vim.health.warn(#stats.failed_abbreviations .. ' abbreviations failed to load:')

    for _, failed in ipairs(stats.failed_abbreviations) do
      vim.health.error('  ' .. failed.line .. ' (' .. failed.error .. ')')
    end
  end

  if #stats.logs > 0 then
    vim.health.info 'Recent activity:'

    for _, entry in ipairs(stats.logs) do
      local level_map = { debug = 'info', info = 'info', warn = 'warn', error = 'error' }
      local health_fn = vim.health[level_map[entry.level]] or vim.health.info
      health_fn(string.format('[%s] %s', entry.timestamp, entry.msg))
    end
  end
end

return M
