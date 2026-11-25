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
      ty = { 'endline', ' # ty: ignore[', ']' },
      default = { 'endline', ' # pyright: ignore[', ']' },
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

M.diag_ignore = function()
  local ignore = M.config.ignores[vim.bo.filetype]
  if not ignore then
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diags = vim.tbl_filter(function(diag)
    return get_spec(ignore, diag) ~= nil
  end, vim.diagnostic.get(0, { lnum = lnum }))
  if diags then
    vim.ui.select(
      diags,
      {
        prompt = "Ignore diagnostic:",
        format_item = function(diag)
          local codestr = get_code(get_spec(ignore, diag), diag)
          codestr = codestr and (" [" .. codestr .. "]") or ""
          return diag.message .. codestr
        end,
      },
      function(choice)
        if not choice then
          return
        end

        local spec = get_spec(ignore, choice)
        local where, prefix, suffix, joiner = unpack(spec)
        if not joiner then
          joiner = ', '
        end
        if not suffix then
          suffix = ''
        end

        local pto, sfrom, col, line
        if where == 'prevline' then
          if lnum > 0 then
            line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
            _, pto = line:find(prefix, 1, true)
          end
          if pto then
            lnum = lnum - 1
          else
            line = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]
            _, col = line:find('^ *')
            local indent = line:sub(1, col)
            line = indent .. prefix .. suffix
            vim.api.nvim_buf_set_lines(0, lnum, lnum, true, { line })
          end
        elseif where == 'endline' then
          line = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, true)[1]
          _, pto = line:find(prefix, 1, true)
          if not pto then
            col = line:len()
            vim.api.nvim_buf_set_text(0, lnum, col, lnum, col, { prefix .. suffix })
            line = line .. prefix .. suffix
          end
        end

        if not pto then
          pto = col + prefix:len()
        end
        if suffix == '' then
          sfrom = line:len() + 1
        else
          sfrom, _ = line:find(suffix, pto + 1, true)
        end
        local ignorestr = string.sub(line, pto + 1, sfrom - 1)
        local types = ignorestr == "" and {} or vim.split(ignorestr, joiner)
        table.insert(types, get_code(spec, choice))
        ignorestr = table.concat(types, joiner)
        vim.api.nvim_buf_set_text(0, lnum, pto, lnum, sfrom - 1, { ignorestr })
      end
    )
  end
end

local function is_type_valid(spec)
  return spec == 'prevline'
      or spec == 'endline'
end

---@param user_config diag_ignore.UserConfig
M.setup = function(user_config)
  ---@type diag_ignore.UserConfig
  user_config = user_config or {}
  M.config = vim.tbl_deep_extend("force", M.default_config, user_config)
  vim.validate({
    ignores = { M.config.ignores, 'table' },
  })

  -- A spec and a source map must not be merged into each other:
  -- if the user's entry has a different shape than the default, it replaces it.
  for ft, ignore in pairs(user_config.ignores or {}) do
    local default = M.default_config.ignores[ft]
    if type(ignore) == 'table' and default and is_spec(ignore) ~= is_spec(default) then
      M.config.ignores[ft] = ignore
    end
  end

  local validators = {}
  local function add_validators(name, spec)
    validators[('%s[1] (type)'):format(name)] = {
      spec[1], is_type_valid, '"prevline" or "endline"'
    }
    validators[('%s[2] (prefix)'):format(name)] = { spec[2], 'string' }
    validators[('%s[3] (suffix)'):format(name)] = { spec[3], { 'string', 'nil' } }
    validators[('%s[4] (joiner)'):format(name)] = { spec[4], { 'string', 'nil' } }
    validators[('%s.code'):format(name)] = { spec.code, { 'string', 'function', 'nil' } }
  end
  for ft, ignore in pairs(M.config.ignores) do
    if is_spec(ignore) then
      add_validators(('ignores.%s'):format(ft), ignore)
    elseif ignore then
      for source, spec in pairs(ignore) do
        if spec then
          add_validators(('ignores.%s.%s'):format(ft, source), spec)
        end
      end
    end
  end
  vim.validate(validators)

  vim.keymap.set('n', '<Plug>(diag_ignore)', M.diag_ignore, {
    silent = true, noremap = true,
  })
end

return M
