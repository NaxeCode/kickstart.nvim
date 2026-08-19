-- C / raylib Overseer task definitions.
--
-- Kept out of lua/plugins/ so it does not declare a second `config` function for
-- overseer.nvim (lua/plugins/overseer.lua already owns that; two specs with
-- `config` for the same plugin collide in lazy.nvim). Templates here register
-- lazily on first use via M.run().

local M = {}

local C_ROOT_MARKERS = { 'Makefile', 'compile_flags.txt', 'compile_commands.json' }

local registered = false

local function c_root()
    local path = vim.api.nvim_buf_get_name(0)
    if path == '' then path = vim.fn.getcwd() end
    return vim.fs.root(path, C_ROOT_MARKERS) or vim.fs.root(path, { '.git' })
end

local function has_makefile(root) return root ~= nil and vim.uv.fs_stat(root .. '/Makefile') ~= nil end

-- Compiler flags shared by the fallback (no-Makefile) build commands.
local RAYLIB_FLAGS = '$(pkg-config --cflags --libs raylib) -lm'
local WARN_FLAGS = '-std=c99 -Wall -Wextra'
local DEBUG_BUILD = ('cc %s -g -O0 -fsanitize=address,undefined *.c -o game %s'):format(WARN_FLAGS, RAYLIB_FLAGS)
local RELEASE_BUILD = ('cc %s -Os -DNDEBUG -ffunction-sections -fdata-sections -Wl,--gc-sections -s *.c -o game %s'):format(WARN_FLAGS, RAYLIB_FLAGS)

local function task_components(opts)
    opts = opts or {}

    local components = {
        { 'unique', replace = true },
        { 'open_output', on_start = 'always', on_complete = 'failure', direction = 'dock', focus = opts.focus_output or false },
    }

    if opts.fold_raylib_startup then components[#components + 1] = 'custom.fold_raylib_startup' end
    components[#components + 1] = 'default'

    return components
end

local function register_templates()
    if registered then return end
    registered = true

    local overseer = require 'overseer'

    local function register_c_task(name, desc, shell_cmd, opts)
        opts = opts or {}
        overseer.register_template {
            name = name,
            desc = desc,
            tags = { overseer.TAG.BUILD },
            condition = {
                callback = function(search)
                    local dir = search and search.dir or vim.fn.getcwd()
                    return vim.fs.find(C_ROOT_MARKERS, { upward = true, path = dir })[1] ~= nil
                end,
            },
            builder = function(params)
                local root = params.cwd or c_root() or vim.fn.getcwd()
                return {
                    name = name,
                    cmd = 'bash',
                    args = { '-lc', shell_cmd(root) },
                    cwd = root,
                    strategy = opts.normal_output and { 'jobstart', use_terminal = false } or nil,
                    components = task_components(opts),
                }
            end,
        }
    end

    -- Each task prefers the project's Makefile when one exists, and otherwise falls
    -- back to compiling every .c in the project root into ./game. That keeps a
    -- brand-new single-file prototype buildable before any build system exists.
    register_c_task(
        'C: build (debug)',
        'Build the raylib project with debug symbols and sanitizers',
        function(root) return has_makefile(root) and 'make' or DEBUG_BUILD end
    )

    register_c_task(
        'C: build (release)',
        'Build the raylib project optimized for size',
        function(root) return has_makefile(root) and 'make release' or RELEASE_BUILD end
    )

    register_c_task(
        'C: run (debug)',
        'Build with debug symbols, then run the game',
        function(root) return (has_makefile(root) and 'make' or DEBUG_BUILD) .. ' && ./game' end,
        { fold_raylib_startup = true, normal_output = true }
    )

    register_c_task('C: clean', 'Remove build artifacts', function(root) return has_makefile(root) and 'make clean' or 'rm -f game *.o' end)

    -- Binary size report - relevant for the size-optimization showcase.
    register_c_task(
        'C: size report',
        'Build release and report stripped binary size',
        function(root) return (has_makefile(root) and 'make release' or RELEASE_BUILD) .. ' && size game && ls -lh game && du -h game' end
    )

    -- Generate compile_flags.txt so clangd resolves raylib.h and system headers
    -- without needing bear/compiledb. Run once per new project.
    register_c_task(
        'C: generate compile_flags.txt',
        'Write clangd compile flags (includes raylib) to the project root',
        function()
            return table.concat({
                'printf "%s\\n" -std=c99 -Wall -Wextra > compile_flags.txt',
                'pkg-config --cflags raylib | tr " " "\\n" | grep -v "^$" >> compile_flags.txt',
                'cat compile_flags.txt',
            }, ' && ')
        end
    )
end

function M.register() register_templates() end

function M.root() return c_root() end

local function is_c_task(task, root)
    if not (task.name and task.name:match '^C:') then return false end
    return not root or not task.cwd or task.cwd == root
end

local function save_modified_buffers()
    local ok, err = pcall(function() vim.cmd.wall() end)
    if not ok then
        vim.notify(('Could not save modified buffers; C task not started:\n%s'):format(err), vim.log.levels.ERROR)
        return false
    end
    return true
end

function M.run(name, opts)
    opts = opts or {}
    if opts.save and not save_modified_buffers() then return end

    register_templates()

    local root = c_root()
    if not root then
        vim.notify('No C project root found (Makefile/compile_flags.txt/.git).', vim.log.levels.ERROR)
        return
    end

    local overseer = require 'overseer'
    overseer.run_task({
        name = name,
        cwd = root,
        search_params = { dir = root },
        autostart = false,
    }, function(task, err)
        if not task then
            vim.notify(err or ('Could not create C task: ' .. name), vim.log.levels.ERROR)
            return
        end

        if opts.close_on_success then
            task:subscribe('on_complete', function(_, status)
                if status == require('overseer.constants').STATUS.SUCCESS then vim.schedule(function() require('overseer.window').close() end) end
                return true
            end)
        end

        task:start()
    end)
end

function M.stop(opts)
    opts = opts or {}
    local root = c_root()
    local stopped = 0

    for _, task in ipairs(require('overseer').list_tasks()) do
        if is_c_task(task, root) and task:is_running() and task:stop() then stopped = stopped + 1 end
    end

    if opts.notify ~= false then
        if stopped > 0 then
            vim.notify(('Stopped %d C task%s.'):format(stopped, stopped == 1 and '' or 's'), vim.log.levels.INFO)
        else
            vim.notify('No running C task found.', vim.log.levels.INFO)
        end
    end

    return stopped
end

return M
