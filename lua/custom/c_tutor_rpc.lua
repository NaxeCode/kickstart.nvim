local prompt_contract = require 'custom.c_tutor_prompt'

local M = {}
local Client = {}
Client.__index = Client

local MAX_FRAME_BYTES = 1024 * 1024

local function runtime_dir()
    local path = vim.fn.stdpath 'state' .. '/c-tutor/runtime'
    vim.fn.mkdir(path, 'p')
    pcall(vim.uv.fs_chmod, path, 448) -- 0700
    return path
end

local function default_command(model, thinking_level, service_tier)
    local omp = vim.fn.exepath 'omp'
    if omp == '' then omp = 'omp' end
    return {
        omp,
        '--mode',
        'rpc',
        '--model',
        model,
        '--thinking',
        thinking_level or 'low',
        '--service-tier',
        service_tier or 'priority',
        '--no-tools',
        '--no-lsp',
        '--no-extensions',
        '--no-skills',
        '--no-rules',
        '--no-session',
        '--no-title',
        '--config',
        vim.fn.stdpath 'config' .. '/lua/custom/c_tutor_omp.yml',
        '--system-prompt',
        prompt_contract.SYSTEM,
    }
end

local function response_error(event)
    local value = event.error or event.message
    if type(value) == 'string' and value ~= '' then return value:sub(1, 240) end
    if type(value) == 'table' then
        value = value.message or value.code
        if type(value) == 'string' and value ~= '' then return value:sub(1, 240) end
    end
    return ('OMP rejected %s'):format(event.command or 'the tutor request')
end

function Client.new(opts)
    opts = opts or {}
    return setmetatable({
        backend = 'omp',
        command = opts.command,
        cwd = opts.cwd or runtime_dir(),
        model = opts.model or 'openai-codex/gpt-5.3-codex-spark',
        thinking_level = opts.thinking_level or 'low',
        service_tier = opts.service_tier or 'priority',
        timeout_ms = opts.timeout_ms or 20000,
        on_status = opts.on_status,
        process = nil,
        process_generation = 0,
        ready = false,
        stopping = false,
        stdout_buffer = '',
        stderr_tail = '',
        next_id = 0,
        current = nil,
    }, Client)
end

function Client:_status(value)
    self.state = value
    if self.on_status then self.on_status(value) end
end

function Client:_next_id(prefix)
    self.next_id = self.next_id + 1
    return ('c-tutor-%s-%d'):format(prefix, self.next_id)
end

function Client:_write(value)
    if not self.process then return nil, 'OMP tutor process is not running' end
    local ok, err = pcall(self.process.write, self.process, vim.json.encode(value) .. '\n')
    if not ok then return nil, tostring(err) end
    return true
end

function Client:_terminate()
    local process = self.process
    if not process then return end
    self.process_generation = self.process_generation + 1
    self.process = nil
    self.ready = false
    self.stdout_buffer = ''
    self.stopping = true
    pcall(process.write, process, nil)
    pcall(process.kill, process, 15)
    self:_status 'stopped'
end

function Client:_finish(err, text, event)
    local current = self.current
    self.current = nil
    if not current then return end
    if current.callback then current.callback(err, text, event) end
end

function Client:_fail_and_restart(message)
    self:_terminate()
    self:_finish(message)
end

function Client:_send_prompt()
    local current = self.current
    if not current then return end
    current.stage = 'prompt'
    current.prompt_id = self:_next_id 'prompt'
    local ok, err = self:_write {
        id = current.prompt_id,
        type = 'prompt',
        message = current.message,
    }
    if not ok then self:_fail_and_restart(err) end
end

function Client:_reset_session()
    local current = self.current
    if not current or not self.ready then return end
    current.stage = 'reset'
    current.reset_id = self:_next_id 'reset'
    local ok, err = self:_write {
        id = current.reset_id,
        type = 'new_session',
    }
    if not ok then self:_fail_and_restart(err) end
end

local function assistant_text(message)
    if type(message) ~= 'table' or message.role ~= 'assistant' or type(message.content) ~= 'table' then return nil end
    for index = #message.content, 1, -1 do
        local item = message.content[index]
        if type(item) == 'table' and item.type == 'text' and type(item.text) == 'string' then return item.text end
    end
    return nil
end

function Client:_handle_event(event)
    if event.type == 'ready' then
        self.ready = true
        self.stopping = false
        self:_status 'ready'
        if self.current and self.current.stage == 'waiting-ready' then self:_reset_session() end
        return
    end

    local current = self.current
    if not current then return end

    if event.type == 'response' and current.abort_id and event.id == current.abort_id then
        if event.success == false then
            self:_fail_and_restart(response_error(event))
        else
            self:_status 'ready'
            self:_finish(current.cancel_reason or 'Tutor request cancelled')
        end
        return
    end
    if event.type == 'response' then
        if event.id == current.reset_id then
            if event.success == false then
                self:_fail_and_restart(response_error(event))
            else
                self:_send_prompt()
            end
            return
        end
        if event.id == current.prompt_id and event.success == false then
            self:_fail_and_restart(response_error(event))
            return
        end
    end

    if current.stage ~= 'prompt' then return end

    if event.type == 'message_update' then
        local update = event.assistantMessageEvent
        if type(update) == 'table' and update.type == 'text_end' and type(update.content) == 'string' then current.text = update.content end
        return
    end

    if event.type == 'message_end' then
        current.text = assistant_text(event.message) or current.text
        return
    end

    if event.type == 'agent_end' and event.isTerminal ~= false then
        local text = current.text
        if not text and type(event.messages) == 'table' then
            for index = #event.messages, 1, -1 do
                text = assistant_text(event.messages[index])
                if text then break end
            end
        end
        if text then
            self:_status 'ready'
            self:_finish(nil, text, event)
        else
            self:_fail_and_restart 'OMP tutor completed without a text response'
        end
    end
end

function Client:_consume_stdout(data)
    self.stdout_buffer = self.stdout_buffer .. data
    if #self.stdout_buffer > MAX_FRAME_BYTES and not self.stdout_buffer:find('\n', 1, true) then
        self:_fail_and_restart 'OMP tutor emitted an oversized RPC frame'
        return
    end

    while true do
        local newline = self.stdout_buffer:find('\n', 1, true)
        if not newline then break end
        local line = self.stdout_buffer:sub(1, newline - 1)
        self.stdout_buffer = self.stdout_buffer:sub(newline + 1)
        if line ~= '' then
            if #line > MAX_FRAME_BYTES then
                self:_fail_and_restart 'OMP tutor emitted an oversized RPC frame'
                return
            end
            local ok, event = pcall(vim.json.decode, line)
            if not ok or type(event) ~= 'table' then
                self:_fail_and_restart 'OMP tutor emitted malformed RPC JSON'
                return
            end
            self:_handle_event(event)
        end
    end
end

function Client:start()
    if self.process then return true end
    local command = self.command or default_command(self.model, self.thinking_level, self.service_tier)
    if vim.fn.executable(command[1]) ~= 1 then return nil, ('Tutor executable not found: %s'):format(command[1]) end

    self.process_generation = self.process_generation + 1
    local generation = self.process_generation
    self.ready = false
    self.stopping = false
    self.stdout_buffer = ''
    self.stderr_tail = ''
    self:_status 'starting'

    self.process = vim.system(command, {
        cwd = self.cwd,
        text = true,
        stdin = true,
        stdout = function(err, data)
            if generation ~= self.process_generation then return end
            if err then
                vim.schedule(function()
                    if generation == self.process_generation then self:_fail_and_restart 'Failed to read OMP tutor output' end
                end)
            elseif data then
                vim.schedule(function()
                    if generation == self.process_generation then self:_consume_stdout(data) end
                end)
            end
        end,
        stderr = function(_, data)
            if generation ~= self.process_generation or not data then return end
            self.stderr_tail = (self.stderr_tail .. data):sub(-4096)
        end,
    }, function(result)
        vim.schedule(function()
            if generation ~= self.process_generation then return end
            self.process = nil
            self.ready = false
            self:_status 'stopped'
            if self.current then
                local suffix = result.code and (' (exit %d)'):format(result.code) or ''
                self:_finish('OMP tutor process stopped' .. suffix)
            end
        end)
    end)

    return true
end

function Client:request(message, metadata, callback)
    if self.current then return nil, 'OMP tutor already has a request in flight' end
    if type(message) ~= 'string' or message == '' then return nil, 'Tutor request is empty' end

    local serial = self:_next_id 'request'
    self.current = {
        serial = serial,
        stage = self.ready and 'reset' or 'waiting-ready',
        message = message,
        metadata = metadata,
        callback = callback,
    }

    local ok, err = self:start()
    if not ok then
        self.current = nil
        return nil, err
    end
    if self.ready then self:_reset_session() end

    vim.defer_fn(function()
        if not self.current or self.current.serial ~= serial then return end
        self:_fail_and_restart 'OMP tutor request timed out'
    end, self.timeout_ms)

    return serial
end

function Client:cancel(reason)
    local current = self.current
    if not current then return false end
    local message = reason or 'Tutor request cancelled'
    if not self.ready or current.stage ~= 'prompt' then
        self:_finish(message)
        return true
    end

    current.stage = 'abort'
    current.abort_id = self:_next_id 'abort'
    current.cancel_reason = message
    local ok, err = self:_write {
        id = current.abort_id,
        type = 'abort',
    }
    if not ok then
        self:_fail_and_restart(err)
        return nil, err
    end
    return true
end

function Client:stop()
    if self.current then self:_finish 'Tutor stopped' end
    self:_terminate()
end

function Client:is_busy() return self.current ~= nil end

function Client:status()
    if self.current then return self.current.stage == 'prompt' and 'thinking' or self.current.stage end
    return self.state or 'stopped'
end

local GeminiClient = {}
GeminiClient.__index = GeminiClient

local function write_private_file(path, contents)
    local file, open_error = vim.uv.fs_open(path, 'w', 384)
    if not file then return nil, tostring(open_error) end
    local written, write_error = vim.uv.fs_write(file, contents, 0)
    vim.uv.fs_close(file)
    if not written then
        pcall(vim.uv.fs_unlink, path)
        return nil, tostring(write_error)
    end
    pcall(vim.uv.fs_chmod, path, 384)
    return true
end

local function unlink(path)
    if path then pcall(vim.uv.fs_unlink, path) end
end

local function gemini_model(model) return model:match '^google/(.+)$' or model end

local function gemini_text(response)
    local output = {}
    for _, step in ipairs(response.steps or {}) do
        if type(step) == 'table' and step.type == 'model_output' then
            for _, content in ipairs(step.content or {}) do
                if type(content) == 'table' and content.type == 'text' and type(content.text) == 'string' then output[#output + 1] = content.text end
            end
        end
    end
    if #output == 0 then return nil end
    return table.concat(output)
end

local function bounded_message(value)
    if type(value) ~= 'string' or value == '' then return nil end
    return value:gsub('%s+', ' '):sub(1, 240)
end

local function gemini_error(response, status)
    local message = type(response) == 'table' and type(response.error) == 'table' and bounded_message(response.error.message) or nil
    if message then return ('Gemini API request failed (HTTP %s): %s'):format(status, message) end
    return ('Gemini API request failed (HTTP %s)'):format(status)
end

function GeminiClient.new(opts)
    opts = opts or {}
    return setmetatable({
        backend = 'gemini',
        cwd = opts.cwd or runtime_dir(),
        model = opts.model or 'google/gemini-3.5-flash-lite',
        endpoint = opts.endpoint or 'https://generativelanguage.googleapis.com/v1beta/interactions',
        curl_command = opts.curl_command,
        api_key_env = opts.api_key_env,
        service_tier = opts.service_tier or 'priority',
        thinking_level = opts.thinking_level or 'low',
        timeout_ms = opts.timeout_ms or 20000,
        on_status = opts.on_status,
        state = 'stopped',
        next_id = 0,
        generation = 0,
        current = nil,
    }, GeminiClient)
end

function GeminiClient:_status(value)
    self.state = value
    if self.on_status then self.on_status(value) end
end

function GeminiClient:_next_id()
    self.next_id = self.next_id + 1
    return ('c-tutor-gemini-%d'):format(self.next_id)
end

function GeminiClient:_api_key()
    local key
    if self.api_key_env then
        key = vim.env[self.api_key_env]
    else
        key = vim.env.GEMINI_API_KEY or vim.env.GOOGLE_API_KEY
    end
    if type(key) ~= 'string' or key == '' then
        local name = self.api_key_env or 'GEMINI_API_KEY'
        return nil, ('Tutor credential is missing: export %s on this device'):format(name)
    end
    if key:find '[\r\n]' then return nil, 'Tutor credential contains an invalid newline' end
    return key
end

function GeminiClient:_command(body_path, header_path)
    local command = vim.deepcopy(self.curl_command)
    if not command then
        local curl = vim.fn.exepath 'curl'
        command = { curl ~= '' and curl or 'curl' }
    end
    vim.list_extend(command, {
        '--silent',
        '--show-error',
        '--request',
        'POST',
        self.endpoint,
        '--header',
        'Content-Type: application/json',
        '--header',
        '@-',
        '--data-binary',
        '@' .. body_path,
        '--dump-header',
        header_path,
        '--max-time',
        tostring(math.max(1, math.ceil(self.timeout_ms / 1000))),
        '--write-out',
        '\n%{http_code}',
    })
    return command
end

function GeminiClient:start()
    local command = self:_command('', '')
    if vim.fn.executable(command[1]) ~= 1 then return nil, ('Tutor executable not found: %s'):format(command[1]) end
    local _, key_error = self:_api_key()
    if key_error then
        self:_status 'stopped'
        return nil, key_error
    end
    self:_status 'ready'
    return true
end

function GeminiClient:_cleanup(current)
    unlink(current and current.body_path)
    unlink(current and current.header_path)
end

local function response_service_tier(path)
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.size > 64 * 1024 then return nil end
    local read_ok, lines = pcall(vim.fn.readfile, path)
    if not read_ok then return nil end
    local headers = table.concat(lines, '\n'):lower()
    return headers:match '\nx%-gemini%-service%-tier:%s*([%w_-]+)' or headers:match '^x%-gemini%-service%-tier:%s*([%w_-]+)'
end

function GeminiClient:_finish(generation, result)
    local current = self.current
    if not current or generation ~= self.generation or current.generation ~= generation then return end
    local service_tier = response_service_tier(current.header_path)
    self.current = nil
    self:_cleanup(current)
    self:_status 'ready'

    if result.code ~= 0 then
        local detail = bounded_message(result.stderr) or ('curl exited %d'):format(result.code)
        current.callback(('Gemini API transport failed: %s'):format(detail))
        return
    end

    local stdout = result.stdout or ''
    if #stdout > MAX_FRAME_BYTES then
        current.callback 'Gemini API returned an oversized response'
        return
    end
    local body, status = stdout:match '^(.*)\n(%d%d%d)$'
    if not body then
        current.callback 'Gemini API returned a malformed HTTP response'
        return
    end
    local decoded_ok, response = pcall(vim.json.decode, body)
    if not decoded_ok or type(response) ~= 'table' then
        current.callback 'Gemini API returned malformed JSON'
        return
    end
    if status:sub(1, 1) ~= '2' then
        current.callback(gemini_error(response, status))
        return
    end
    local text = gemini_text(response)
    if not text then
        current.callback 'Gemini API completed without model output text'
        return
    end
    current.callback(nil, text, {
        backend = 'gemini',
        response = response,
        usage = response.usage,
        service_tier = service_tier,
    })
end

function GeminiClient:request(message, metadata, callback)
    if self.current then return nil, 'Gemini tutor already has a request in flight' end
    if type(message) ~= 'string' or message == '' then return nil, 'Tutor request is empty' end
    if type(callback) ~= 'function' then return nil, 'Tutor request callback is required' end
    local started, start_error = self:start()
    if not started then return nil, start_error end
    local key, key_error = self:_api_key()
    if not key then return nil, key_error end

    local payload = {
        model = gemini_model(self.model),
        input = prompt_contract.SYSTEM .. '\n\n' .. message,
        store = false,
        service_tier = self.service_tier,
        generation_config = { thinking_level = self.thinking_level },
    }
    local encoded_ok, encoded = pcall(vim.json.encode, payload)
    if not encoded_ok then return nil, 'Failed to encode Gemini tutor request' end

    local serial = self:_next_id()
    local body_path = ('%s/%s-body.json'):format(self.cwd, serial)
    local header_path = ('%s/%s-headers.txt'):format(self.cwd, serial)
    vim.fn.mkdir(self.cwd, 'p')
    pcall(vim.uv.fs_chmod, self.cwd, 448)
    local written, write_error = write_private_file(body_path, encoded)
    if not written then return nil, 'Failed to write private Gemini request: ' .. tostring(write_error) end

    self.generation = self.generation + 1
    local generation = self.generation
    local current = {
        serial = serial,
        generation = generation,
        callback = callback,
        metadata = metadata,
        body_path = body_path,
        header_path = header_path,
    }
    self.current = current
    self:_status 'thinking'
    current.process = vim.system(self:_command(body_path, header_path), {
        cwd = self.cwd,
        text = true,
        stdin = 'x-goog-api-key: ' .. key .. '\n',
    }, function(result)
        vim.schedule(function() self:_finish(generation, result) end)
    end)

    vim.defer_fn(function()
        if self.current and self.current.serial == serial then self:cancel 'Gemini tutor request timed out' end
    end, self.timeout_ms)
    return serial
end

function GeminiClient:cancel(reason)
    local current = self.current
    if not current then return false end
    self.generation = self.generation + 1
    self.current = nil
    if current.process then pcall(current.process.kill, current.process, 15) end
    self:_cleanup(current)
    self:_status 'ready'
    current.callback(reason or 'Tutor request cancelled')
    return true
end

function GeminiClient:stop()
    if self.current then self:cancel 'Tutor stopped' end
    self:_status 'stopped'
end

function GeminiClient:is_busy() return self.current ~= nil end

function GeminiClient:status() return self.current and 'thinking' or self.state end

local function new_client(opts)
    opts = opts or {}
    local backend = opts.backend
    if not backend then
        if opts.command then
            backend = 'omp'
        elseif type(opts.model) == 'string' and opts.model:match '^google/' then
            backend = 'gemini'
        else
            backend = 'omp'
        end
    end
    if backend == 'omp' then return Client.new(opts) end
    if backend == 'gemini' then return GeminiClient.new(opts) end
    error(('Unsupported C tutor backend: %s'):format(tostring(backend)))
end

M.new = new_client
M.default_command = default_command

return M
