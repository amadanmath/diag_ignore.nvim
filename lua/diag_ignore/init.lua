---@class diag_ignore.UserConfig
---@field ignores table<string, diag_ignore.IgnoreSpec | diag_ignore.SourceMap> | nil

---@class diag_ignore.IgnoreSpec
---@field [1] string
---@field [2] string
---@field [3] string | nil
---@field [4] string | nil
---@field code string | function | nil

---Maps `diagnostic.source` to a spec; `default` is used for unlisted sources.
---@alias diag_ignore.SourceMap table<string, diag_ignore.IgnoreSpec | false>

local M = {}

---@type diag_ignore.UserConfig
M.default_config = {
  ignores = {
    python = {
      ty = { 'endline', '  # ty: ignore[', ']' },
      Ruff = { 'endline', '  # noqa: ' },
      default = { 'endline', '  # pyright: ignore[', ']' },
    },
    lua = { 'prevline', '---@diagnostic disable-next-line: ' },
  },
}

local function is_spec(ignore)
  return type(ignore) == 'table' and type(ignore[1]) == 'string'
end

local function get_spec(ignore, diag)
  if is_spec(ignore) then
    return ignore
  end
  local spec = ignore[diag.source]
  if spec == nil then
    spec = ignore.default
  end
  return spec or nil
end

local function get_code(ignore, diag)
  local code_field = ignore.code or 'code'
  local field_type = type(code_field)
  local codestr
  if field_type == "string" then
    codestr = diag[code_field]
  elseif field_type == "function" then
    codestr = code_field(diag)
  end
  return codestr
end

local function notify(msg, level)
  vim.notify('diag_ignore: ' .. msg, level)
end

local function get_line(lnum)
  return vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]
end

-- Returns the start and end of the last plain-text occurrence of `needle`.
local function find_last(s, needle)
  local from, to
  local init = 1
  while true do
    local f, t = s:find(needle, init, true)
    if not f then
      return from, to
    end
    from, to = f, t
    init = f + 1
  end
end

M.diag_ignore = function()
  local ignore = M.config.ignores[vim.bo.filetype]
  if not ignore then
    notify(('no annotation configured for filetype "%s"'):format(vim.bo.filetype), vim.log.levels.WARN)
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  -- Keep only diagnostics that can be ignored, one per annotation and code.
  local seen = {}
  local diags = vim.tbl_filter(function(diag)
    local spec = get_spec(ignore, diag)
    local code = spec and get_code(spec, diag)
    if code == nil then
      return false
    end
    code = tostring(code)
    seen[spec] = seen[spec] or {}
    if seen[spec][code] then
      return false
    end
    seen[spec][code] = true
    return true
  end, vim.diagnostic.get(0, { lnum = lnum }))
  if #diags == 0 then
    notify('no diagnostics to ignore on this line', vim.log.levels.INFO)
    return
  end

  vim.ui.select(
    diags,
    {
      prompt = "Ignore diagnostic:",
      format_item = function(diag)
        return ('%s [%s]'):format(diag.message, get_code(get_spec(ignore, diag), diag))
      end,
    },
    function(choice)
      if not choice then
        return
      end

      local spec = get_spec(ignore, choice)
      local code = tostring(get_code(spec, choice))
      local where, prefix, suffix, joiner = unpack(spec)
      suffix = suffix or ''
      joiner = joiner or ', '

      -- Look for an existing annotation; leading whitespace of the prefix is
      -- not required to match.
      local search = (prefix:gsub('^%s+', ''))
      local target = where == 'prevline' and lnum - 1 or lnum
      local line, pto
      if target >= 0 then
        line = get_line(target)
        _, pto = find_last(line, search)
      end

      if not pto then
        local annotation = prefix .. code .. suffix
        if where == 'prevline' then
          local indent = get_line(lnum):match('^%s*')
          vim.api.nvim_buf_set_lines(0, lnum, lnum, true, { indent .. annotation })
        else
          vim.api.nvim_buf_set_text(0, lnum, #line, lnum, #line, { annotation })
        end
        return
      end

      local sfrom
      if suffix == '' then
        -- Without a suffix, the code list ends at the next comment or at the end of line.
        sfrom = line:find('%s+#', pto + 1) or (#line + 1)
      else
        sfrom = line:find(suffix, pto + 1, true)
        if not sfrom then
          notify(('existing annotation is missing "%s"'):format(suffix), vim.log.levels.ERROR)
          return
        end
      end
      local existing = line:sub(pto + 1, sfrom - 1)
      local codes = existing == '' and {} or vim.split(existing, joiner, { plain = true })
      for _, c in ipairs(codes) do
        if vim.trim(c) == code then
          notify(('"%s" is already ignored'):format(code), vim.log.levels.INFO)
          return
        end
      end
      table.insert(codes, code)
      vim.api.nvim_buf_set_text(0, target, pto, target, sfrom - 1, { table.concat(codes, joiner) })
    end
  )
end

local function is_type_valid(spec)
  return spec == 'prevline'
      or spec == 'endline'
end

-- `vim.validate{...}` is deprecated since Nvim 0.11, but the replacement
-- signature does not exist before it.
local function validate(name, value, validator, optional, message)
  if vim.fn.has('nvim-0.11') == 1 then
    vim.validate(name, value, validator, optional, message)
  else
    vim.validate({ [name] = { value, validator, message or optional } })
  end
end

---@param user_config diag_ignore.UserConfig
M.setup = function(user_config)
  ---@type diag_ignore.UserConfig
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.default_config, user_config)
  validate('ignores', M.config.ignores, 'table')

  -- A spec and a source map must not be merged into each other:
  -- if the user's entry has a different shape than the default, it replaces it.
  for ft, ignore in pairs(user_config.ignores or {}) do
    local default = M.default_config.ignores[ft]
    if type(ignore) == 'table' and default and is_spec(ignore) ~= is_spec(default) then
      M.config.ignores[ft] = ignore
    end
  end

  local function validate_spec(name, spec)
    validate(('%s[1] (type)'):format(name), spec[1], is_type_valid, false, '"prevline" or "endline"')
    validate(('%s[2] (prefix)'):format(name), spec[2], 'string')
    validate(('%s[3] (suffix)'):format(name), spec[3], 'string', true)
    validate(('%s[4] (joiner)'):format(name), spec[4], 'string', true)
    validate(('%s.code'):format(name), spec.code, { 'string', 'function' }, true)
  end
  for ft, ignore in pairs(M.config.ignores) do
    if is_spec(ignore) then
      validate_spec(('ignores.%s'):format(ft), ignore)
    elseif ignore then
      for source, spec in pairs(ignore) do
        if spec then
          validate_spec(('ignores.%s.%s'):format(ft, source), spec)
        end
      end
    end
  end

  vim.keymap.set('n', '<Plug>(diag_ignore)', M.diag_ignore, {
    silent = true, noremap = true,
  })
end

return M
