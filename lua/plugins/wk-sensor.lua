-- workloop sensor — appends editor events to ~/.local/share/workloop/events.jsonl
--
-- Records metadata only: which file, how many diagnostics, what you searched for,
-- how many build errors. Never file contents.

local WK_HOME = vim.env.WK_HOME or (vim.env.HOME .. '/.local/share/workloop')
local LOG = WK_HOME .. '/events.jsonl'

local function log(ev)
    ev.epoch = os.time()
    ev.t = os.date '!%Y-%m-%dT%H:%M:%SZ'
    local ok, line = pcall(vim.json.encode, ev)
    if not ok then return end
    vim.fn.mkdir(WK_HOME, 'p')
    local fh = io.open(LOG, 'a')
    if not fh then return end
    fh:write(line .. '\n')
    fh:close()
end

local function rel(path)
    if path == nil or path == '' then return nil end
    -- Autocmds hand out relative paths in some events (`:w`) and absolute in others.
    -- Subtracting the absolute root length from a relative path overruns to '', so
    -- normalise first and verify the prefix actually matches before slicing.
    path = vim.fn.fnamemodify(path, ':p')
    local root = vim.fs.root(path, { '.git' })
    if root and path:sub(1, #root + 1) == root .. '/' then return path:sub(#root + 2) end
    return vim.fn.fnamemodify(path, ':t')
end

local group = vim.api.nvim_create_augroup('WorkloopSensor', { clear = true })

-- Writes are the clearest proof of work: no writes for N minutes while a buffer
-- is open is the primary stall signal.
vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(a)
        if vim.bo[a.buf].buftype ~= '' then return end
        log { ev = 'write', file = rel(a.file), ft = vim.bo[a.buf].filetype, lines = vim.api.nvim_buf_line_count(a.buf) }
    end,
})

vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(a)
        if vim.bo[a.buf].buftype ~= '' or a.file == '' then return end
        log { ev = 'open', file = rel(a.file), ft = vim.bo[a.buf].filetype }
    end,
})

-- Diagnostics trend: a count that will not go down is a stuck signal.
local diag_timer = nil
vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = group,
    callback = function(a)
        if diag_timer then diag_timer:stop() end
        diag_timer = vim.defer_fn(function()
            local d = vim.diagnostic.get(a.buf)
            local errors, warns = 0, 0
            for _, x in ipairs(d) do
                if x.severity == vim.diagnostic.severity.ERROR then
                    errors = errors + 1
                elseif x.severity == vim.diagnostic.severity.WARN then
                    warns = warns + 1
                end
            end
            log { ev = 'diag', file = rel(vim.api.nvim_buf_get_name(a.buf)), errors = errors, warns = warns }
        end, 3000)
    end,
})

-- Telescope live_grep / grep_string queries. Repeated searches for the same
-- symbol mean you are hunting for something you cannot name yet.
vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'TelescopePrompt',
    callback = function(a)
        local last = ''
        vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
            buffer = a.buf,
            callback = function()
                local l = vim.api.nvim_buf_get_lines(a.buf, 0, 1, false)[1]
                if l and #l > 1 then last = l end
            end,
        })
        vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufLeave' }, {
            buffer = a.buf,
            once = true,
            callback = function()
                if #last > 1 then log { ev = 'grep', q = vim.trim(last:gsub('^[>%s]+', '')) } end
            end,
        })
    end,
})

-- :make / dotnet build results (makeprg is set to `dotnet build` for C# buffers).
vim.api.nvim_create_autocmd('QuickFixCmdPost', {
    group = group,
    pattern = { 'make', 'cfile', 'cgetfile' },
    callback = function()
        local qf = vim.fn.getqflist()
        local errs = 0
        for _, e in ipairs(qf) do
            if e.type == 'E' or e.type == '' then errs = errs + 1 end
        end
        log { ev = 'build', errors = errs, total = #qf }
    end,
})

vim.api.nvim_create_autocmd({ 'FocusLost', 'FocusGained' }, {
    group = group,
    callback = function(a) log { ev = a.event == 'FocusLost' and 'away' or 'back' } end,
})

-- Ex-commands you type. This is the cheapest window into editor habits there is:
-- forty `:w`, `:e path/to/file` instead of the picker, `:bd` churn, hand-rolled
-- `:%s///` where an LSP rename exists. Far lighter than logging keystrokes.
--
-- Metadata mode records only the command name, never its arguments, because a
-- substitution or a search can carry content from the buffer.
vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    callback = function()
        if vim.v.event.abort then return end
        local line = vim.fn.getcmdline()
        local kind = vim.fn.getcmdtype()
        if not line or line == '' then return end
        if kind == ':' then
            local full = vim.env.WK_MODE == 'full'
            local name = line:match '^%s*[%%%d,%.%$%+%-]*(%a+)' or line:match '^%s*(%p)' or '?'
            log { ev = 'ex', cmd = full and line or name }
        elseif kind == '/' or kind == '?' then
            log { ev = 'search' } -- that you searched, never what for
        end
    end,
})

local function wk(args)
    return function() vim.cmd('botright 12split | terminal wk ' .. args) end
end

vim.keymap.set('n', '<leader>ws', wk 'start', { desc = '[W]orkloop [s]tart session' })
vim.keymap.set('n', '<leader>wa', wk 'ask', { desc = '[W]orkloop [a]sk (escalate one rung)' })
vim.keymap.set('n', '<leader>wq', wk 'stop', { desc = '[W]orkloop stop + retro' })
vim.keymap.set('n', '<leader>wn', wk 'note', { desc = '[W]orkloop [n]ote' })
vim.keymap.set('n', '<leader>ww', function() vim.cmd '!wk status' end, { desc = '[W]orkloop status' })

return {}
