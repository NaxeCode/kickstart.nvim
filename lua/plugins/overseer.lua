local function haxeflixel_root()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then path = vim.fn.getcwd() end

  return vim.fs.root(path, { 'Project.xml', 'project.xml' }) or vim.fs.root(path, function(name) return name:match '%.hxml$' ~= nil end)
end

local function run_haxeflixel_task(name)
  local root = haxeflixel_root()
  if not root then
    vim.notify('No HaxeFlixel/Lime project root found. Open a file under a Project.xml project.', vim.log.levels.ERROR)
    return
  end

  require('overseer').run_task {
    name = name,
    cwd = root,
    search_params = { dir = root },
  }
end

return {
  'stevearc/overseer.nvim',
  opts = {},
  config = function(_, opts)
    local overseer = require 'overseer'
    overseer.setup(opts)

    local function task_components()
      return {
        { 'open_output', on_start = 'always', on_complete = 'failure', direction = 'dock', focus = false },
        'default',
      }
    end

    local function register_haxe_task(name, desc, cmd, args)
      overseer.register_template {
        name = name,
        desc = desc,
        tags = { overseer.TAG.BUILD },
        condition = {
          callback = function(search)
            local dir = search and search.dir or vim.fn.getcwd()
            return vim.fs.find({ 'Project.xml', 'project.xml' }, { upward = true, path = dir })[1] ~= nil
          end,
        },
        builder = function(params)
          return {
            name = name,
            cmd = cmd,
            args = args,
            cwd = params.cwd or haxeflixel_root() or vim.fn.getcwd(),
            components = task_components(),
          }
        end,
      }
    end

    register_haxe_task(
      'HaxeFlixel: build HL debug',
      'Refresh display.hxml, then compile HashLink debug target with Lime',
      'bash',
      { '-lc', 'SDL_VIDEODRIVER=x11 lime display hl -debug > display.hxml && SDL_VIDEODRIVER=x11 lime build hl -debug' }
    )

    register_haxe_task(
      'HaxeFlixel: run HL debug',
      'Refresh display.hxml, then run HashLink debug target with Lime',
      'bash',
      { '-lc', 'SDL_VIDEODRIVER=x11 lime display hl -debug > display.hxml && SDL_VIDEODRIVER=x11 lime test hl -debug' }
    )

    register_haxe_task('HaxeFlixel: build Linux debug', 'Compile native Linux debug target with Lime', 'lime', { 'build', 'linux', '-debug' })

    register_haxe_task(
      'HaxeFlixel: generate display.hxml',
      'Generate Haxe language-server compiler args from Lime HL debug target',
      'bash',
      { '-lc', 'lime display hl -debug > display.hxml' }
    )

    register_haxe_task('Haxe: compile unit tests HL', 'Compile HashLink unit tests', 'haxe', { 'test_hl.hxml' })

    register_haxe_task('Haxe: run unit tests HL', 'Run previously compiled HashLink unit tests', 'bash', {
      '-lc',
      'LD_LIBRARY_PATH="/home/naxecode/haxelib/lime/8,3,1/ndll/Linux64:/home/naxecode/haxelib/openfl/9,5,1/ndll/Linux64:${LD_LIBRARY_PATH}" hl unit_tests.hl',
    })
  end,
  keys = {
    { '<leader>or', '<cmd>OverseerRun<cr>', desc = 'Overseer: Run task' },
    { '<leader>ot', '<cmd>OverseerToggle<cr>', desc = 'Overseer: Task list' },
    { '<leader>oa', '<cmd>OverseerTaskAction<cr>', desc = 'Overseer: Task action' },
    { '<leader>os', '<cmd>OverseerShell<cr>', desc = 'Overseer: Shell task' },
    { '<leader>xb', function() run_haxeflixel_task 'HaxeFlixel: build HL debug' end, desc = 'HaxeFlixel: build HL debug' },
    { '<leader>xr', function() run_haxeflixel_task 'HaxeFlixel: run HL debug' end, desc = 'HaxeFlixel: run HL debug' },
    { '<leader>xl', function() run_haxeflixel_task 'HaxeFlixel: build Linux debug' end, desc = 'HaxeFlixel: build Linux debug' },
    { '<leader>xd', function() run_haxeflixel_task 'HaxeFlixel: generate display.hxml' end, desc = 'HaxeFlixel: generate display.hxml' },
    { '<leader>xc', function() run_haxeflixel_task 'Haxe: compile unit tests HL' end, desc = 'Haxe: compile unit tests HL' },
    { '<leader>xt', function() run_haxeflixel_task 'Haxe: run unit tests HL' end, desc = 'Haxe: run unit tests HL' },
  },
}
