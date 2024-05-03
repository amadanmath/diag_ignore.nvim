# `diag_ignore.nvim`

`diag_ignore.nvim` automates inserting of annotations to disable diagnostic
checks in a line of code. Upon triggering the `diag_ignore` mapping, the user
is presented with all the diagnostic messages on the current line. If the user
selects a diagnostic code, the code will be ignored on the current line.

Currently supported languages are Lua (lua_ls) and Python (basedpyright,
pyright).

Use your favourite plugin manager to install `diag_ignore.nvim`.
For example, a minimal plugin spec with Lazy.nvim:

```lua
    {
      "amadanmath/diag_ignore.nvim",
      keys = {
        { '<Leader>ci', '<Plug>(diag_ignore)', mode = 'n', desc = 'Diagnostic: ignore' },
      },
      opts = {},
    }
```

The default options are:

```lua
    opts = {
      ignores = {
        python = { 'endline',  ' # pyright: ignore[', ']' },
        lua =    { 'prevline', '---@diagnostic disable-next-line: ' },
      },
    },
```

The `ignores` option lists the supported filetypes. Each value is a table:

```lua
    [filetype] = { type, prefix, suffix, joiner }
```

If `suffix` is `nil`, the default is `''` (empty string).
If `joiner` is `nil`, the default is `', '` (comma and space).

If `type` is `'endline'`, the annotation will be appended to the current line.
For example, in Python, invoking `diag_ignore.nvim` on

```python
    1
```

will result in

```python
    1 # pyright: ignore[reportUnusedExpression]
```

If `type` is `'prevline'`, the annotation will be inserted on the previous line.
For example, in Lua, invoking `diag_ignore.nvim` on

```lua
    1
```

will result in

```lua
    ---@diagnostic disable-next-line: exp-in-action
    1
```

If an annotation already exists and an additional diagnostic code is selected,
the code will be inserted into the existing annotation, separated from the
existing codes by `joiner`.

The default Python config is based on pyright/basedpyright. If you are using
mypy, you will have to change the Python config as follows:

```lua
    python = { 'endline',  ' # type: ignore[', ']' },
```
