---@class diag_ignore.UserConfig
---@field ignores table<string, string[]>

local M = {}

---@type diag_ignore.UserConfig
M.default_config = {
  ignores = {
    python = { 'endline', ' # pyright: ignore[', ']' },
    lua = { 'prevline', '---@diagnostic disable-next-line: ' },
    go = { 'endline', ' //nolint ', '', ' , ', 'source' },
  },
}

M.diag_ignore = function()
  local ignore = M.config.ignores[vim.bo.filetype]
  if not ignore then
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diags = vim.diagnostic.get(0, { lnum = lnum })
  local where, prefix, suffix, joiner, codestr_source = unpack(ignore)
  if diags then
    vim.ui.select(
      diags,
      {
        prompt = "Ignore diagnostic:",
        format_item = function(diag)
          local codestr = diag.code and (" [" .. diag.code .. "]") or ""
          if codestr_source == 'source' then
            codestr = diag.source and (" [" .. diag.source .. "]") or ""
          end
          return diag.message .. codestr
        end,
      },
      function(choice)
        if not choice then
          return
        end

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
        if codestr_source == 'source' then
          table.insert(types, choice.source)
        else
          table.insert(types, choice.code)
        end
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
  M.config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
  vim.validate({
    ignores = { M.config.ignores, 'table' },
  })

  local validators = {}
  for ft, ignore in pairs(M.config.ignores) do
    if ignore then
      validators[('ignores.%s[1] (type)'):format(ft)] = { ignore[1], is_type_valid, '"prevline" or "endline"' }
      validators[('ignores.%s[2] (prefix)'):format(ft)] = { ignore[2], 'string' }
      validators[('ignores.%s[3] (suffix)'):format(ft)] = { ignore[3], { 'string', 'nil' } }
      validators[('ignores.%s[4] (joiner)'):format(ft)] = { ignore[4], { 'string', 'nil' } }
    end
  end
  vim.validate(validators)

  vim.keymap.set('n', '<Plug>(diag_ignore)', M.diag_ignore, {
    silent = true, noremap = true,
  })
end

return M
