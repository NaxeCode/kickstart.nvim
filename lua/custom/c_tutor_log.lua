local M = {}

local state = {
    fd = nil,
    path = nil,
    session = nil,
    sequence = 0,
    last_error = nil,
    max_bytes = nil,
}

local function timestamp()
    local seconds, microseconds = vim.uv.gettimeofday()
    return os.date('!%Y-%m-%dT%H:%M:%S', seconds) .. ('.%03dZ'):format(math.floor(microseconds / 1000))
end

local function close_file()
    if not state.fd then return end
    pcall(vim.uv.fs_fsync, state.fd)
    pcall(vim.uv.fs_close, state.fd)
    state.fd = nil
end

local function open_file()
    local fd, err = vim.uv.fs_open(state.path, 'a', 384)
    if not fd then
        state.last_error = tostring(err)
        return false
    end
    state.fd = fd
    pcall(vim.uv.fs_chmod, state.path, 384)
    return true
end

local function rotate(path, max_bytes)
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.size <= max_bytes then return false end
    pcall(vim.uv.fs_unlink, path .. '.1')
    local ok, err = vim.uv.fs_rename(path, path .. '.1')
    if not ok then state.last_error = tostring(err) end
    return ok ~= nil
end

local function ensure_capacity(incoming_bytes)
    if not state.fd or not state.max_bytes then return false end
    local stat, stat_error = vim.uv.fs_fstat(state.fd)
    if not stat then
        state.last_error = tostring(stat_error)
        return false
    end
    if stat.size == 0 or stat.size + incoming_bytes <= state.max_bytes then return true end

    close_file()
    pcall(vim.uv.fs_unlink, state.path .. '.1')
    local renamed, rename_error = vim.uv.fs_rename(state.path, state.path .. '.1')
    if not renamed then
        state.last_error = tostring(rename_error)
        open_file()
        return false
    end
    return open_file()
end

local function append(payload)
    local remaining = payload
    while #remaining > 0 do
        local written, err = vim.uv.fs_write(state.fd, remaining, -1)
        if not written or written <= 0 then
            state.last_error = tostring(err or 'short write')
            return false
        end
        remaining = remaining:sub(written + 1)
    end
    return true
end

function M.event(name, fields)
    if not state.fd or type(name) ~= 'string' or name == '' then return false end
    state.sequence = state.sequence + 1
    local entry = vim.tbl_extend('force', fields or {}, {
        timestamp = timestamp(),
        session = state.session,
        sequence = state.sequence,
        event = name,
    })
    local ok, encoded = pcall(vim.json.encode, entry)
    if not ok then
        state.last_error = tostring(encoded)
        return false
    end
    local payload = encoded .. '\n'
    if not ensure_capacity(#payload) then return false end
    return append(payload)
end

function M.setup(opts)
    opts = opts or {}
    close_file()
    state.path = assert(opts.path, 'tutor log path is required')
    state.session = opts.session or ('%d-%d'):format(vim.uv.os_getpid(), vim.uv.hrtime())
    state.sequence = 0
    state.last_error = nil
    state.max_bytes = math.max(1, tonumber(opts.max_bytes) or (1024 * 1024))

    local directory = vim.fs.dirname(state.path)
    vim.fn.mkdir(directory, 'p')
    pcall(vim.uv.fs_chmod, directory, 448)
    local rotated = rotate(state.path, state.max_bytes)
    if not open_file() then return false, state.last_error end
    M.event('session_start', { rotated = rotated })
    return true
end

function M.stop()
    if not state.fd then return end
    M.event 'session_stop'
    close_file()
end

function M.path() return state.path end

function M.last_error() return state.last_error end

return M
