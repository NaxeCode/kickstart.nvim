local prompt_contract = require 'custom.c_tutor_prompt'
local render = require 'custom.c_tutor_render'
local rpc = require 'custom.c_tutor_rpc'
local logger = require 'custom.c_tutor_log'
local languages = require 'custom.tutor_languages'
local schedule_namespace = vim.api.nvim_create_namespace 'c_tutor_schedule'

local M = {}

local defaults = {
    model = 'meta/muse-spark-1.2-contributor',
    backend = 'omp',
    service_tier = 'none',
    thinking_level = 'low',
    default_mode = 'coach',
    request_timeout_ms = 20000,
    ask_debounce_ms = 250,
    max_source_bytes = 256 * 1024,
    git_check = true,
    state_dir = vim.fn.stdpath 'state' .. '/c-tutor',
    log_max_bytes = 1024 * 1024,
}

local config = vim.deepcopy(defaults)
local state = {
    setup = false,
    client = nil,
    client_status = 'stopped',
    saved = { modes = {} },
    schedules = {},
    request_generation = 0,
    active = nil,
    queue = {},
    last_response = {},
    disclosed = {},
    cache = {},
    annotations = {},
    projects = {},
}

local function notify(message, level) vim.notify(message, level or vim.log.levels.INFO, { title = 'Tutor' }) end

local function state_path() return config.state_dir .. '/state.json' end
local MAX_STATE_BYTES = 1024 * 1024
local MAX_CACHE_BYTES = 2 * 1024 * 1024

local function read_json(path, max_bytes)
    local stat = vim.uv.fs_stat(path)
    if max_bytes and stat and stat.size > max_bytes then return nil, 'too_large' end
    local read_ok, lines = pcall(vim.fn.readfile, path)
    if not read_ok then return nil, 'read_failed' end
    local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if not decode_ok or type(decoded) ~= 'table' then return nil, 'invalid_json' end
    return decoded
end

local function write_json(path, value, success_event, failure_event)
    local encode_ok, encoded = pcall(vim.json.encode, value)
    if not encode_ok then
        logger.event(failure_event, { reason = 'encode_failed' })
        return false
    end
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    local temporary = path .. '.tmp'
    local write_ok, result = pcall(vim.fn.writefile, { encoded }, temporary)
    if not write_ok or result ~= 0 then
        pcall(vim.uv.fs_unlink, temporary)
        logger.event(failure_event, { reason = 'write_failed' })
        return false
    end
    pcall(vim.uv.fs_chmod, temporary, 384)
    local renamed = vim.uv.fs_rename(temporary, path)
    if not renamed then
        pcall(vim.uv.fs_unlink, temporary)
        logger.event(failure_event, { reason = 'rename_failed' })
        return false
    end
    pcall(vim.uv.fs_chmod, path, 384)
    logger.event(success_event)
    return true
end

local function load_state()
    vim.fn.mkdir(config.state_dir, 'p')
    pcall(vim.uv.fs_chmod, config.state_dir, 448)
    local path = state_path()
    if not vim.uv.fs_stat(path) then
        logger.event('state_load_skipped', { reason = 'missing' })
        return
    end
    local decoded, err = read_json(path, MAX_STATE_BYTES)
    if not decoded or type(decoded.modes) ~= 'table' then
        state.saved.modes = {}
        logger.event('state_load_failed', { reason = err or 'invalid_schema' })
        return
    end
    local modes = {}
    local rejected = 0
    for key, mode in pairs(decoded.modes) do
        if type(key) == 'string' and #key == 64 and key:match '^[a-f0-9]+$' and (mode == 'off' or mode == 'ask' or mode == 'coach') then
            modes[key] = mode
        else
            rejected = rejected + 1
        end
    end
    state.saved.modes = modes
    logger.event('state_loaded', { modes = vim.tbl_count(modes), rejected = rejected })
end

local function save_state() return write_json(state_path(), { modes = state.saved.modes }, 'state_written', 'state_write_failed') end

local CACHE_VERSION = 'tutor-responses-v7'
local CACHE_LIMIT = 256

local function cache_path() return config.state_dir .. '/answers.json' end

local function provenance_valid(value)
    return type(value) == 'table'
        and type(value.model) == 'string'
        and value.model ~= ''
        and (value.thinking_level == false or (type(value.thinking_level) == 'string' and value.thinking_level ~= ''))
end

local function prune_cache()
    local keys = vim.tbl_keys(state.cache)
    if #keys <= CACHE_LIMIT then return 0 end
    table.sort(keys, function(left, right)
        local left_entry = state.cache[left]
        local right_entry = state.cache[right]
        return (type(left_entry) == 'table' and left_entry.updated_at or 0) < (type(right_entry) == 'table' and right_entry.updated_at or 0)
    end)
    local pruned = #keys - CACHE_LIMIT
    for index = 1, pruned do
        state.cache[keys[index]] = nil
    end
    return pruned
end

local function load_cache()
    local path = cache_path()
    if not vim.uv.fs_stat(path) then
        logger.event('cache_load_skipped', { reason = 'missing' })
        return
    end
    local decoded, err = read_json(path, MAX_CACHE_BYTES)
    if not decoded or decoded.version ~= CACHE_VERSION or type(decoded.entries) ~= 'table' then
        state.cache = {}
        logger.event('cache_load_failed', { reason = err or 'invalid_schema_or_version' })
        return
    end

    local entries = {}
    local rejected = 0
    local function nonnegative_finite(value) return type(value) == 'number' and value >= 0 and value == value and value < math.huge end
    local cache_interactions = { ask = true, diagnostic = true, more = true }
    for key, entry in pairs(decoded.entries) do
        local valid = type(key) == 'string'
            and key:match '^[a-f0-9]+$' ~= nil
            and #key == 64
            and type(entry) == 'table'
            and type(entry.response) == 'table'
            and (entry.elapsed_seconds == nil or nonnegative_finite(entry.elapsed_seconds))
            and (entry.updated_at == nil or nonnegative_finite(entry.updated_at))
            and cache_interactions[entry.interaction] == true
            and provenance_valid(entry.provenance)
        if valid then
            entries[key] = entry
        else
            rejected = rejected + 1
        end
    end
    state.cache = entries
    local pruned = prune_cache()
    logger.event('cache_loaded', { entries = vim.tbl_count(entries), rejected = rejected, pruned = pruned })
end

local function save_cache()
    prune_cache()
    return write_json(cache_path(), { version = CACHE_VERSION, entries = state.cache }, 'cache_persisted', 'cache_write_failed')
end
local function normalize_question(question) return question:lower():gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '') end
local function cache_profile()
    return table.concat({
        config.command and 'omp' or config.backend or '',
        config.model or '',
        config.thinking_level or 'none',
    }, '\0')
end

local function marker_cache_key(root, relative_path, question)
    local root_id = vim.fn.sha256(root or '')
    return vim.fn.sha256(table.concat({ CACHE_VERSION, cache_profile(), 'marker', root_id, relative_path or '', normalize_question(question) }, '\0'))
end
local function marker_question_for(request)
    if type(request.marker_question) == 'string' and request.marker_question ~= '' then return request.marker_question end
    if request.interaction == 'ask' then return request.question end
    return nil
end

local function cache_key_for(request)
    local marker_question = marker_question_for(request)
    if marker_question then return marker_cache_key(request.root, request.relative_path, marker_question) end
    if request.interaction ~= 'diagnostic' then return nil end
    local diagnostic = request.diagnostic or {}
    return vim.fn.sha256(vim.json.encode {
        CACHE_VERSION,
        cache_profile(),
        'diagnostic',
        request.relative_path or '',
        tostring(request.anchor_line or ''),
        request.context or '',
        tostring(diagnostic.line or ''),
        tostring(diagnostic.column or ''),
        diagnostic.severity or '',
        diagnostic.source or '',
        diagnostic.code or '',
        diagnostic.message or '',
    })
end

local function question_id(question) return question and vim.fn.sha256('tutor-question\0' .. normalize_question(question)):sub(1, 12) or nil end
local function response_provenance(source, event)
    local client = state.client
    local thinking_level = client and client.thinking_level
    if type(thinking_level) ~= 'string' or thinking_level == '' then thinking_level = false end
    local service_tier = event and event.service_tier or (client and client.service_tier)
    if type(service_tier) ~= 'string' or service_tier == '' then service_tier = false end
    return {
        model = (client and client.model) or config.model,
        thinking_level = thinking_level,
        backend = (client and client.backend) or config.backend,
        service_tier = service_tier,
        source = source,
        generated_at = os.time(),
    }
end

local function log_request(event, request, fields)
    fields = fields or {}
    local mark_id = fields.mark_id
    local current_line = mark_id and render.position(request.bufnr, mark_id) or nil
    logger.event(
        event,
        vim.tbl_extend('force', {
            interaction = request.interaction,
            bufnr = request.bufnr,
            file = request.relative_path,
            line = current_line or request.anchor_line,
            question_id = question_id(request.question),
        }, fields)
    )
end

local function root_key(root) return vim.fn.sha256(root) end

local function mode_for_root(root) return state.saved.modes[root_key(root)] or config.default_mode end

local function set_mode_for_root(root, mode)
    state.saved.modes[root_key(root)] = mode
    save_state()
end

local function hidden_relative_path(relative)
    for part in relative:gmatch '[^/]+' do
        if part:sub(1, 1) == '.' then return true end
    end
    return false
end

local function ignored_path(root, relative)
    if not config.git_check or not vim.uv.fs_stat(root .. '/.git') then return false end
    local result = vim.system({ 'git', '-C', root, 'check-ignore', '--quiet', '--', relative }, { text = true }):wait(500)
    if result.code == 0 then return true end
    if result.code == 1 then return false end
    return true
end

local function project_info(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then return nil, 'invalid buffer' end
    if vim.api.nvim_get_option_value('buftype', { buf = bufnr }) ~= '' then return nil, 'special buffer' end

    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == '' then return nil, 'unnamed buffer' end
    path = vim.fs.normalize(path)

    local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
    local profile, profile_error = languages.for_buffer(filetype, path)
    if not profile then return nil, profile_error end

    local cached = state.projects[bufnr]
    if cached and cached.path == path and cached.profile == profile then
        return {
            root = cached.root,
            relative_path = cached.relative_path,
            path = cached.path,
            profile = cached.profile,
            mode = mode_for_root(cached.root),
        }
    end

    local root = vim.fs.root(path, { '.tutor' })
    if not root then return nil, 'outside a .tutor project' end
    root = vim.fs.normalize(root)
    local relative = vim.fs.relpath(root, path) or path:sub(#root + 2)
    if relative == '' or relative:sub(1, 2) == '..' then return nil, 'source is outside the tutor root' end
    if hidden_relative_path(relative) then return nil, 'hidden source path' end

    local basename = vim.fs.basename(path):lower()
    if basename:find 'secret' or basename:find 'credential' or basename:find 'token' or basename:find 'password' then
        return nil, 'credential-like source path'
    end
    if ignored_path(root, relative) then return nil, 'ignored source path' end

    state.projects[bufnr] = {
        root = root,
        relative_path = relative,
        path = path,
        profile = profile,
    }
    return {
        root = root,
        relative_path = relative,
        path = path,
        profile = profile,
        mode = mode_for_root(root),
    }
end

local function refresh_buffer_mode(bufnr)
    local info = project_info(bufnr)
    vim.b[bufnr].c_tutor_mode = info and info.mode or nil
    if not info or info.mode ~= 'coach' then return info end
    local key = root_key(info.root)
    if state.disclosed[key] then return info end
    state.disclosed[key] = true
    notify(
        ('%s tutor markers active: // tutor:, // coach:, // t:, and // c: send only their explicit questions. Use <leader>mt to turn the tutor off.'):format(
            info.profile.display
        )
    )
    return info
end

local restore_cached_annotations

local function activate_buffer(bufnr)
    local info = refresh_buffer_mode(bufnr)
    if info then
        logger.event('buffer_activated', {
            bufnr = bufnr,
            file = info.relative_path,
            mode = info.mode,
            changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
        })
    end
    if info and info.mode ~= 'off' and state.client then
        state.client:start()
        if restore_cached_annotations then restore_cached_annotations(bufnr) end
    end
end

local function marker_question(line)
    if type(line) ~= 'string' then return nil end
    local label, question = line:match '^%s*//%s*([%a]+)%s*:%s*(.-)%s*$'
    if not label or question == '' then return nil end
    label = label:lower()
    if label ~= 'tutor' and label ~= 'coach' and label ~= 't' and label ~= 'c' then return nil end
    return question, label
end

local function log_editor_event(trigger, bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        logger.event('buffer_event', { trigger = trigger, bufnr = bufnr, valid = false })
        return
    end
    local info = project_info(bufnr)
    local fields = {
        trigger = trigger,
        bufnr = bufnr,
        file = info and info.relative_path or nil,
        mode = info and info.mode or 'off',
        changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    }
    local window = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == bufnr then
        fields.line = vim.api.nvim_win_get_cursor(window)[1]
        local line = vim.api.nvim_buf_get_lines(bufnr, fields.line - 1, fields.line, false)[1]
        local question, label = marker_question(line)
        fields.marker = question ~= nil
        fields.marker_label = label
        fields.question_id = question_id(question)
    end
    logger.event('buffer_event', fields)
end

local function source_context(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local numbered = {}
    for index, line in ipairs(lines) do
        numbered[index] = ('%d:%s'):format(index, line)
    end
    local text = table.concat(numbered, '\n')
    if #text > config.max_source_bytes then return nil, ('source buffer exceeds the %d KiB complete-context limit'):format(config.max_source_bytes / 1024) end
    return text, 1, #lines
end

local severity_names = {
    [vim.diagnostic.severity.ERROR] = 'error',
    [vim.diagnostic.severity.WARN] = 'warning',
    [vim.diagnostic.severity.INFO] = 'information',
    [vim.diagnostic.severity.HINT] = 'hint',
}

local function root_diagnostic(bufnr, preferred_line)
    local diagnostics = vim.diagnostic.get(bufnr)
    if #diagnostics == 0 then return nil end

    local on_line = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.lnum == preferred_line - 1 then on_line[#on_line + 1] = diagnostic end
    end
    local candidates = #on_line > 0 and on_line or diagnostics
    local has_error = false
    for _, diagnostic in ipairs(candidates) do
        if diagnostic.severity == vim.diagnostic.severity.ERROR then
            has_error = true
            break
        end
    end
    if has_error then candidates = vim.tbl_filter(function(diagnostic) return diagnostic.severity == vim.diagnostic.severity.ERROR end, candidates) end
    table.sort(candidates, function(left, right)
        if left.lnum ~= right.lnum then return left.lnum < right.lnum end
        if left.col ~= right.col then return left.col < right.col end
        return (left.severity or 99) < (right.severity or 99)
    end)
    return candidates[1]
end

local function diagnostic_payload(diagnostic)
    if not diagnostic then return nil end
    local message = tostring(diagnostic.message or '')
    if #message > 1800 then message = message:sub(1, 1800) end
    return {
        line = diagnostic.lnum + 1,
        column = diagnostic.col + 1,
        severity = severity_names[diagnostic.severity] or 'unknown',
        source = diagnostic.source,
        code = diagnostic.code and tostring(diagnostic.code) or nil,
        message = message,
    }
end

local function request_for(bufnr, anchor_line, interaction, question, previous)
    local info, info_error = project_info(bufnr)
    if not info then return nil, info_error end
    if info.mode == 'off' then return nil, 'tutor mode is off' end

    local context, context_start, context_end = source_context(bufnr, anchor_line)
    if not context then return nil, context_start end
    local diagnostic = diagnostic_payload(root_diagnostic(bufnr, anchor_line))
    if interaction == 'diagnostic' and not diagnostic then return nil, 'No diagnostic is available in this buffer' end

    local outbound = context .. '\n' .. vim.json.encode(diagnostic or {}) .. '\n' .. (question or '')
    if prompt_contract.contains_secret(outbound) then return nil, 'Tutor request blocked because the selected context looks secret-bearing' end
    if #vim.json.encode(diagnostic or {}) > 2048 then return nil, 'Tutor diagnostic metadata exceeds 2 KiB' end

    return {
        interaction = interaction,
        question = question,
        previous_response = previous,
        bufnr = bufnr,
        root = info.root,
        relative_path = info.relative_path,
        profile = info.profile,
        anchor_line = anchor_line,
        context = context,
        context_start = context_start,
        context_end = context_end,
        diagnostic = diagnostic,
        changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
        mode = info.mode,
        explicit = interaction ~= 'coach',
    }
end

local function annotation_bucket(bufnr)
    local bucket = state.annotations[bufnr]
    if not bucket then
        bucket = {}
        state.annotations[bufnr] = bucket
    end
    return bucket
end

local function annotation_at(bufnr, line_number, question)
    for id, annotation in pairs(state.annotations[bufnr] or {}) do
        if render.position(bufnr, id) == line_number and marker_question_for(annotation.request) == question then return annotation, id end
    end
end

local function refresh_last_response(bufnr)
    local newest
    local newest_order = -1
    for mark_id, annotation in pairs(state.annotations[bufnr] or {}) do
        local mark = render.get(bufnr, mark_id)
        if annotation.response and mark and (mark.order or 0) > newest_order then
            newest = {
                request = annotation.request,
                response = annotation.response,
                elapsed_seconds = mark.elapsed_seconds,
                mark_id = mark_id,
                cached = annotation.cached,
            }
            newest_order = mark.order or 0
        end
    end
    state.last_response[bufnr] = newest
end

local function response_at_line(bufnr, line_number)
    local selected
    local newest_order = -1
    for mark_id, annotation in pairs(state.annotations[bufnr] or {}) do
        local mark = render.get(bufnr, mark_id)
        if annotation.response and mark and render.position(bufnr, mark_id) == line_number and (mark.order or 0) > newest_order then
            selected = {
                request = annotation.request,
                response = annotation.response,
                elapsed_seconds = mark.elapsed_seconds,
                mark_id = mark_id,
                cached = annotation.cached,
            }
            newest_order = mark.order or 0
        end
    end
    return selected
end

local function remove_annotation(bufnr, mark_id, reason)
    local bucket = state.annotations[bufnr]
    local annotation = bucket and bucket[mark_id]
    if annotation then
        log_request('annotation_removed', annotation.request, {
            mark_id = mark_id,
            phase = annotation.phase or (annotation.cached and 'cached' or 'response'),
            reason = reason or 'unspecified',
        })
    end
    render.clear(bufnr, mark_id)
    if bucket then
        bucket[mark_id] = nil
        if next(bucket) == nil then state.annotations[bufnr] = nil end
    end
    for index = #state.queue, 1, -1 do
        if state.queue[index].mark_id == mark_id then table.remove(state.queue, index) end
    end
    local last = state.last_response[bufnr]
    if last and last.mark_id == mark_id then refresh_last_response(bufnr) end
end

local function marker_matches(bufnr, mark_id, question)
    local line_number = render.position(bufnr, mark_id)
    if not line_number then return false end
    local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1]
    return marker_question(line) == question
end

local function request_hash_tracked(bufnr, hash, ignored_mark_id)
    for mark_id, annotation in pairs(state.annotations[bufnr] or {}) do
        if mark_id ~= ignored_mark_id and annotation.request.hash == hash then return true end
    end
    return false
end

local function store_cached_answer(request, response, elapsed_seconds, provenance)
    if not request.cache_key then return end
    state.cache[request.cache_key] = {
        response = vim.deepcopy(response),
        elapsed_seconds = elapsed_seconds,
        updated_at = os.time(),
        interaction = request.interaction,
        previous_response = vim.deepcopy(request.previous_response),
        provenance = vim.deepcopy(provenance),
    }
    save_cache()
    log_request('cache_written', request, {
        entries = vim.tbl_count(state.cache),
        model = provenance.model,
        thinking_level = provenance.thinking_level or 'none',
    })
end

local function show_cached_answer(request, entry, existing_mark_id)
    if type(entry) ~= 'table' or not provenance_valid(entry.provenance) then
        state.cache[request.cache_key] = nil
        save_cache()
        log_request('cache_entry_invalid', request, { reason = 'missing_or_invalid_provenance' })
        return false
    end
    local validation_request = request
    if entry.interaction == 'more' and request.interaction == 'ask' then
        validation_request = vim.deepcopy(request)
        validation_request.interaction = 'more'
        validation_request.marker_question = request.question
        validation_request.previous_response = entry.previous_response
    elseif entry.interaction ~= request.interaction then
        state.cache[request.cache_key] = nil
        save_cache()
        log_request('cache_entry_invalid', request, { reason = 'interaction_mismatch' })
        return false
    end

    local response = vim.deepcopy(entry.response)
    response.anchor_line = validation_request.anchor_line
    local decoded = prompt_contract.decode(vim.json.encode(response), validation_request)
    if not decoded then
        state.cache[request.cache_key] = nil
        save_cache()
        log_request('cache_entry_invalid', request)
        return false
    end
    local provenance = vim.deepcopy(entry.provenance)
    provenance.source = 'cache'
    local mark_id = render.show(
        validation_request.bufnr,
        validation_request.anchor_line,
        decoded,
        entry.elapsed_seconds,
        provenance,
        existing_mark_id,
        validation_request.profile
    )
    if existing_mark_id and mark_id ~= existing_mark_id then remove_annotation(validation_request.bufnr, existing_mark_id) end
    annotation_bucket(validation_request.bufnr)[mark_id] = {
        request = validation_request,
        response = decoded,
        provenance = provenance,
        cached = true,
    }
    state.last_response[validation_request.bufnr] = {
        request = validation_request,
        response = decoded,
        provenance = provenance,
        elapsed_seconds = entry.elapsed_seconds,
        mark_id = mark_id,
        cached = true,
    }
    log_request('request_cache_hit', validation_request, {
        mark_id = mark_id,
        model = provenance.model,
        thinking_level = provenance.thinking_level or 'none',
    })
    log_request('request_completed', validation_request, {
        mark_id = mark_id,
        source = 'cache',
        model = provenance.model,
        thinking_level = provenance.thinking_level or 'none',
        kind = decoded.kind,
        elapsed_ms = math.floor((entry.elapsed_seconds or 0) * 1000),
    })
    return true
end

local function stale(request, mark_id)
    if not vim.api.nvim_buf_is_valid(request.bufnr) or not vim.api.nvim_buf_is_loaded(request.bufnr) then return true end
    if mode_for_root(request.root) == 'off' or not render.exists(request.bufnr, mark_id) then return true end
    local marker_question = marker_question_for(request)
    if marker_question then return not marker_matches(request.bufnr, mark_id, marker_question) end
    return vim.api.nvim_buf_get_changedtick(request.bufnr) ~= request.changedtick
end

local run_next

local function prepare_request(request)
    local prompt = prompt_contract.build(request)
    request.hash = vim.fn.sha256(prompt)
    request.cache_key = cache_key_for(request)
    return prompt
end

local function refresh_pending_request(request, mark_id)
    if not mark_id then return request end
    local marker_question = marker_question_for(request)
    if not marker_question then return request end
    local line_number = render.position(request.bufnr, mark_id)
    if not line_number or not marker_matches(request.bufnr, mark_id, marker_question) then return nil end
    local refreshed = request_for(request.bufnr, line_number, request.interaction, request.question, request.previous_response)
    if not refreshed then return nil end
    refreshed.marker_question = marker_question
    refreshed.replace_mark_id = request.replace_mark_id
    refreshed.bypass_cache = request.bypass_cache
    refreshed.reroll = request.reroll
    return refreshed
end

local function handle_result(generation, request, mark_id, err, text, event)
    if generation ~= state.request_generation then
        log_request('request_result_ignored', request, {
            generation = generation,
            current_generation = state.request_generation,
            mark_id = mark_id,
            reason = 'superseded',
        })
        run_next()
        return
    end
    state.active = nil

    if err then
        log_request('request_failed', request, { generation = generation, mark_id = mark_id, reason = tostring(err):sub(1, 240) })
        remove_annotation(request.bufnr, mark_id, 'request_failed')
        if request.explicit then notify(err, vim.log.levels.ERROR) end
        run_next()
        return
    end
    if stale(request, mark_id) then
        log_request('request_stale', request, { generation = generation, mark_id = mark_id })
        remove_annotation(request.bufnr, mark_id, 'stale_result')
        run_next()
        return
    end

    local response, decode_error = prompt_contract.decode(text, request)
    if not response then
        log_request('request_failed', request, {
            generation = generation,
            mark_id = mark_id,
            reason = 'invalid_response',
            detail = tostring(decode_error):sub(1, 240),
        })
        remove_annotation(request.bufnr, mark_id, 'invalid_response')
        if request.explicit then notify(decode_error, vim.log.levels.ERROR) end
        run_next()
        return
    end
    if response.kind == 'silence' then
        log_request('request_silence', request, { generation = generation, mark_id = mark_id })
        remove_annotation(request.bufnr, mark_id, 'silence')
        run_next()
        return
    end

    if marker_question_for(request) then response.anchor_line = request.anchor_line end
    local elapsed_seconds = (vim.uv.hrtime() - request.started_at) / 1000000000
    local provenance = response_provenance('fresh', event)
    local rendered_id = render.show(request.bufnr, response.anchor_line, response, elapsed_seconds, provenance, mark_id, request.profile)
    if rendered_id ~= mark_id then remove_annotation(request.bufnr, mark_id, 'extmark_recreated') end
    annotation_bucket(request.bufnr)[rendered_id] = {
        request = request,
        response = response,
        provenance = provenance,
    }
    if request.replace_mark_id and request.replace_mark_id ~= rendered_id then
        remove_annotation(request.bufnr, request.replace_mark_id, request.reroll and 'replaced_by_reroll' or 'replaced_by_deeper_request')
    end
    state.last_response[request.bufnr] = {
        request = request,
        response = response,
        provenance = provenance,
        elapsed_seconds = elapsed_seconds,
        mark_id = rendered_id,
    }
    store_cached_answer(request, response, elapsed_seconds, provenance)
    log_request('request_completed', request, {
        generation = generation,
        mark_id = rendered_id,
        source = 'fresh',
        model = provenance.model,
        thinking_level = provenance.thinking_level or 'none',
        kind = response.kind,
        elapsed_ms = math.floor(elapsed_seconds * 1000),
    })
    run_next()
end

local function start_request(request, mark_id)
    local original_request = request
    request = refresh_pending_request(request, mark_id)
    if not request then
        if mark_id then remove_annotation(original_request.bufnr, mark_id, 'pending_marker_stale') end
        log_request('request_stale', original_request, { mark_id = mark_id, reason = 'pending_marker_stale' })
        return false, 'stale pending tutor request'
    end
    local prompt = prepare_request(request)
    if not request.bypass_cache and request.interaction ~= 'ask' and request_hash_tracked(request.bufnr, request.hash, mark_id) then
        if mark_id then remove_annotation(request.bufnr, mark_id, 'duplicate_request') end
        log_request('request_duplicate', request, { mark_id = mark_id })
        return false, 'duplicate tutor request'
    end
    local cached = not request.bypass_cache and request.interaction ~= 'more' and request.cache_key and state.cache[request.cache_key] or nil
    if cached and show_cached_answer(request, cached, mark_id) then return false, 'cached tutor answer' end

    state.request_generation = state.request_generation + 1
    local generation = state.request_generation
    request.started_at = vim.uv.hrtime()
    mark_id = render.show_thinking(request.bufnr, request.anchor_line, request.started_at, mark_id)
    annotation_bucket(request.bufnr)[mark_id] = { request = request, phase = 'active' }
    state.active = { generation = generation, request = request, mark_id = mark_id }
    log_request('request_started', request, {
        generation = generation,
        mark_id = mark_id,
        queue_depth = #state.queue,
    })
    local serial, err = state.client:request(
        prompt,
        request,
        function(result_error, text, event) handle_result(generation, request, mark_id, result_error, text, event) end
    )
    if not serial then
        state.active = nil
        log_request('request_failed', request, { generation = generation, mark_id = mark_id, reason = tostring(err):sub(1, 240) })
        remove_annotation(request.bufnr, mark_id, 'request_start_failed')
        if request.explicit then notify(err, vim.log.levels.ERROR) end
        return false, err
    end
    return true
end

run_next = function()
    if state.active or state.client:is_busy() then return false end
    while #state.queue > 0 do
        local entry = table.remove(state.queue, 1)
        log_request('request_dequeued', entry.request, { mark_id = entry.mark_id, queue_depth = #state.queue })
        if render.exists(entry.request.bufnr, entry.mark_id) then
            local started = start_request(entry.request, entry.mark_id)
            if started then return true end
        end
    end
    return false
end

function M._dispatch(request)
    prepare_request(request)
    if request.interaction == 'ask' then
        if not request.bypass_cache and annotation_at(request.bufnr, request.anchor_line, request.question) then
            log_request('request_duplicate', request, { reason = 'marker_already_tracked' })
            return false, 'duplicate tutor marker'
        end
    elseif not request.bypass_cache and request_hash_tracked(request.bufnr, request.hash) then
        log_request('request_duplicate', request, { reason = 'request_hash' })
        return false, 'duplicate tutor request'
    end
    local cached = not request.bypass_cache and request.interaction ~= 'more' and request.cache_key and state.cache[request.cache_key] or nil
    if cached and show_cached_answer(request, cached) then return true, 'cached tutor answer' end

    if state.active or state.client:is_busy() then
        local mark_id = render.track(request.bufnr, request.anchor_line)
        annotation_bucket(request.bufnr)[mark_id] = { request = request, phase = 'pending' }
        state.queue[#state.queue + 1] = { request = request, mark_id = mark_id }
        log_request('request_queued', request, { mark_id = mark_id, queue_depth = #state.queue })
        return true, 'queued tutor request'
    end

    return start_request(request)
end

local function ask_line(bufnr, line_number)
    local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1]
    local question = marker_question(line)
    if not question then
        logger.event('marker_dispatch_rejected', { bufnr = bufnr, line = line_number, reason = 'no_marker' })
        return false, 'No // tutor:, // coach:, // t:, or // c: question is on the current line'
    end
    local request, err = request_for(bufnr, line_number, 'ask', question)
    if not request then
        logger.event('marker_dispatch_rejected', {
            bufnr = bufnr,
            line = line_number,
            question_id = question_id(question),
            reason = tostring(err):sub(1, 240),
        })
        notify(err, vim.log.levels.WARN)
        return false, err
    end
    log_request('marker_dispatched', request)
    return M._dispatch(request)
end

restore_cached_annotations = function(bufnr)
    local info = project_info(bufnr)
    if not info or info.mode == 'off' then return end
    local restored = 0
    for line_number, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local question = marker_question(line)
        if question and not annotation_at(bufnr, line_number, question) then
            local cache_key = marker_cache_key(info.root, info.relative_path, question)
            local cached = state.cache[cache_key]
            if cached then
                local request = request_for(bufnr, line_number, 'ask', question)
                if request then
                    request.cache_key = cache_key
                    request.hash = vim.fn.sha256(prompt_contract.build(request))
                    if show_cached_answer(request, cached) then restored = restored + 1 end
                end
            end
        end
    end
    if restored > 0 then logger.event('cache_reconciled', { bufnr = bufnr, file = info.relative_path, restored = restored }) end
end
local function schedule_bucket(bufnr)
    local bucket = state.schedules[bufnr]
    if not bucket then
        bucket = {}
        state.schedules[bufnr] = bucket
    end
    return bucket
end

local function schedule_position(bufnr, schedule_id)
    if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, schedule_namespace, schedule_id, {})
    return #position > 0 and position[1] + 1 or nil
end

local function drop_schedule(bufnr, schedule_id, reason)
    local bucket = state.schedules[bufnr]
    local entry = bucket and bucket[schedule_id]
    local line_number = entry and schedule_position(bufnr, schedule_id) or nil
    if vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_del_extmark, bufnr, schedule_namespace, schedule_id) end
    if bucket then
        bucket[schedule_id] = nil
        if next(bucket) == nil then state.schedules[bufnr] = nil end
    end
    if entry then
        logger.event('marker_debounce_dropped', {
            bufnr = bufnr,
            schedule_id = schedule_id,
            trigger = entry.trigger,
            line = line_number or entry.line,
            question_id = question_id(entry.question),
            reason = reason,
        })
    end
end

local function prune_schedules(bufnr)
    for schedule_id, entry in pairs(state.schedules[bufnr] or {}) do
        local line_number = schedule_position(bufnr, schedule_id)
        local line = line_number and vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1] or nil
        if not line_number or marker_question(line) ~= entry.question then drop_schedule(bufnr, schedule_id, 'marker_changed_or_deleted') end
    end
end

local function clear_schedules(bufnr, reason)
    local ids = vim.tbl_keys(state.schedules[bufnr] or {})
    for _, schedule_id in ipairs(ids) do
        drop_schedule(bufnr, schedule_id, reason)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_clear_namespace, bufnr, schedule_namespace, 0, -1) end
    state.schedules[bufnr] = nil
end

local function cancel_buffer_work(bufnr, reason)
    clear_schedules(bufnr, reason)
    local pending_marks = {}
    for _, entry in ipairs(state.queue) do
        if entry.request.bufnr == bufnr then pending_marks[#pending_marks + 1] = entry.mark_id end
    end
    for _, mark_id in ipairs(pending_marks) do
        remove_annotation(bufnr, mark_id, reason)
    end

    local active = state.active and state.active.request.bufnr == bufnr and state.active or nil
    if active then
        state.request_generation = state.request_generation + 1
        state.active = nil
        remove_annotation(bufnr, active.mark_id, reason)
        state.client:cancel(reason)
    else
        run_next()
    end
    logger.event('buffer_work_cancelled', {
        bufnr = bufnr,
        reason = reason,
        active_cancelled = active ~= nil,
        pending_cancelled = #pending_marks,
    })
end

local function debounce_marker(bufnr, line_number, question, delay, trigger)
    if annotation_at(bufnr, line_number, question) then
        logger.event('marker_debounce_dropped', {
            bufnr = bufnr,
            trigger = trigger,
            line = line_number,
            question_id = question_id(question),
            reason = 'already_tracked',
        })
        return false
    end

    for schedule_id in pairs(state.schedules[bufnr] or {}) do
        if schedule_position(bufnr, schedule_id) == line_number then drop_schedule(bufnr, schedule_id, 'rescheduled') end
    end
    local schedule_id = vim.api.nvim_buf_set_extmark(bufnr, schedule_namespace, line_number - 1, 0, {
        right_gravity = false,
    })
    schedule_bucket(bufnr)[schedule_id] = {
        question = question,
        line = line_number,
        trigger = trigger,
    }
    logger.event('marker_debounce_scheduled', {
        bufnr = bufnr,
        schedule_id = schedule_id,
        trigger = trigger,
        line = line_number,
        question_id = question_id(question),
        delay_ms = delay,
    })
    vim.defer_fn(function()
        local entry = state.schedules[bufnr] and state.schedules[bufnr][schedule_id]
        if not entry then return end
        if not vim.api.nvim_buf_is_valid(bufnr) then
            state.schedules[bufnr][schedule_id] = nil
            logger.event('marker_debounce_dropped', {
                bufnr = bufnr,
                schedule_id = schedule_id,
                question_id = question_id(question),
                reason = 'invalid_buffer',
            })
            return
        end
        local current_line = schedule_position(bufnr, schedule_id)
        local line = current_line and vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1] or nil
        if not current_line or marker_question(line) ~= question then
            drop_schedule(bufnr, schedule_id, 'marker_changed_or_deleted')
            return
        end
        pcall(vim.api.nvim_buf_del_extmark, bufnr, schedule_namespace, schedule_id)
        state.schedules[bufnr][schedule_id] = nil
        if next(state.schedules[bufnr]) == nil then state.schedules[bufnr] = nil end
        logger.event('marker_debounce_fired', {
            bufnr = bufnr,
            schedule_id = schedule_id,
            trigger = trigger,
            line = current_line,
            question_id = question_id(question),
        })
        ask_line(bufnr, current_line)
    end, delay)
    return true
end
local function current_marker(bufnr)
    local info = project_info(bufnr)
    if not info or info.mode == 'off' then return nil end
    local window = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_buf(window) ~= bufnr then window = vim.fn.bufwinid(bufnr) end
    if window == -1 then return nil end
    local line_number = vim.api.nvim_win_get_cursor(window)[1]
    local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1]
    local question = marker_question(line)
    return question and line_number or nil, question
end

local function anticipate_buffer(bufnr)
    local line_number = current_marker(bufnr)
    if not line_number then return false end
    return ask_line(bufnr, line_number)
end
local function schedule_current_marker(bufnr, delay, trigger)
    local line_number, question = current_marker(bufnr)
    if not line_number then return false end
    return debounce_marker(bufnr, line_number, question, delay, trigger or 'manual')
end

local function invalidate(bufnr)
    prune_schedules(bufnr)
    local cancel_active = false
    local removed = 0
    for mark_id, annotation in pairs(state.annotations[bufnr] or {}) do
        local request = annotation.request
        local marker_question = marker_question_for(request)
        local keep = marker_question and marker_matches(bufnr, mark_id, marker_question)
        if not keep then
            if state.active and state.active.mark_id == mark_id then cancel_active = true end
            local reason = marker_question and 'marker_changed_or_deleted' or 'buffer_changed'
            remove_annotation(bufnr, mark_id, reason)
            removed = removed + 1
        end
    end

    if cancel_active then
        state.request_generation = state.request_generation + 1
        state.active = nil
        state.client:cancel 'Tutor marker changed or was deleted'
    else
        run_next()
    end
    restore_cached_annotations(bufnr)
    logger.event('buffer_reconciled', {
        bufnr = bufnr,
        changedtick = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_changedtick(bufnr) or nil,
        removed = removed,
        active_cancelled = cancel_active,
        queue_depth = #state.queue,
        annotations = vim.tbl_count(state.annotations[bufnr] or {}),
    })
end

local function clear_buffer(bufnr, reason)
    clear_schedules(bufnr, reason or 'buffer_cleared')
    for index = #state.queue, 1, -1 do
        if state.queue[index].request.bufnr == bufnr then table.remove(state.queue, index) end
    end
    local cancel_active = state.active and state.active.request.bufnr == bufnr
    if cancel_active then
        state.request_generation = state.request_generation + 1
        state.active = nil
    end
    render.clear(bufnr)
    state.annotations[bufnr] = nil
    state.last_response[bufnr] = nil
    if cancel_active and state.client then
        state.client:cancel(reason or 'Tutor annotations cleared')
    else
        run_next()
    end
    logger.event('buffer_cleared', {
        bufnr = bufnr,
        reason = reason or 'Tutor annotations cleared',
        active_cancelled = cancel_active,
        queue_depth = #state.queue,
    })
end

local function reconcile_eligibility(bufnr, reason)
    local was_tracked = state.projects[bufnr] ~= nil or state.annotations[bufnr] ~= nil or state.schedules[bufnr] ~= nil or vim.b[bufnr].c_tutor_mode ~= nil
    state.projects[bufnr] = nil
    local info = project_info(bufnr)
    if info then
        activate_buffer(bufnr)
        return info
    end
    vim.b[bufnr].c_tutor_mode = nil
    if was_tracked then clear_buffer(bufnr, reason or 'Tutor buffer became ineligible') end
    return nil
end

function M.ask_current()
    local bufnr = vim.api.nvim_get_current_buf()
    return ask_line(bufnr, vim.api.nvim_win_get_cursor(0)[1])
end

function M.explain_diagnostic()
    local bufnr = vim.api.nvim_get_current_buf()
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local diagnostic = root_diagnostic(bufnr, current_line)
    if not diagnostic then
        notify('No diagnostic is available in this buffer', vim.log.levels.INFO)
        return false
    end
    local request, err = request_for(bufnr, diagnostic.lnum + 1, 'diagnostic', 'Explain this diagnostic without correcting the project code.')
    if not request then
        notify(err, vim.log.levels.WARN)
        return false
    end
    return M._dispatch(request)
end

function M.more()
    local bufnr = vim.api.nvim_get_current_buf()
    local previous = response_at_line(bufnr, vim.api.nvim_win_get_cursor(0)[1]) or state.last_response[bufnr]
    if not previous then
        notify('No tutor response is available to deepen', vim.log.levels.INFO)
        return false
    end
    local anchor_line = render.position(bufnr, previous.mark_id) or previous.response.anchor_line
    local request, err = request_for(bufnr, anchor_line, 'more', 'Give one deeper layer of explanation or one more specific hint.', previous.response)
    if not request then
        notify(err, vim.log.levels.WARN)
        return false
    end
    request.marker_question = marker_question_for(previous.request)
    request.replace_mark_id = previous.mark_id
    return M._dispatch(request)
end

function M.reroll()
    local bufnr = vim.api.nvim_get_current_buf()
    local previous = response_at_line(bufnr, vim.api.nvim_win_get_cursor(0)[1]) or state.last_response[bufnr]
    if not previous then
        notify('No tutor response is available to reroll', vim.log.levels.INFO)
        return false
    end
    local anchor_line = render.position(bufnr, previous.mark_id) or previous.response.anchor_line
    local prior_request = previous.request
    local request, err = request_for(bufnr, anchor_line, prior_request.interaction, prior_request.question, prior_request.previous_response)
    if not request then
        notify(err, vim.log.levels.WARN)
        return false
    end
    request.marker_question = marker_question_for(prior_request)
    request.replace_mark_id = previous.mark_id
    request.bypass_cache = true
    request.reroll = true
    log_request('request_rerolled', request, {
        mark_id = previous.mark_id,
        previous_source = previous.cached and 'cache' or 'fresh',
        previous_model = previous.provenance and previous.provenance.model or 'unknown',
    })
    return M._dispatch(request)
end

function M.dismiss()
    local bufnr = vim.api.nvim_get_current_buf()
    local line_number = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1]
    local question = marker_question(line)
    local mark_id
    if question then
        local _, found_mark_id = annotation_at(bufnr, line_number, question)
        mark_id = found_mark_id
    end
    if not mark_id then
        local newest_order = -1
        for candidate in pairs(state.annotations[bufnr] or {}) do
            if render.position(bufnr, candidate) == line_number then
                local mark = render.get(bufnr, candidate)
                if mark and (mark.order or 0) > newest_order then
                    mark_id = candidate
                    newest_order = mark.order or 0
                end
            end
        end
    end
    if not mark_id then return false end
    local annotation = state.annotations[bufnr] and state.annotations[bufnr][mark_id]
    if annotation and annotation.response and marker_question_for(annotation.request) then
        notify('Remove the // tutor:, // coach:, // t:, or // c: marker to remove its permanent decoration', vim.log.levels.INFO)
        log_request('annotation_dismiss_rejected', annotation.request, { mark_id = mark_id, reason = 'permanent_marker' })
        return false
    end

    local cancel_active = state.active and state.active.mark_id == mark_id
    if cancel_active then
        state.request_generation = state.request_generation + 1
        state.active = nil
    end
    remove_annotation(bufnr, mark_id, 'user_dismissed')
    if cancel_active then
        state.client:cancel 'Tutor response dismissed'
    else
        run_next()
    end
    return true
end

function M.mode(mode)
    local bufnr = vim.api.nvim_get_current_buf()
    local info, err = project_info(bufnr)
    if not info then
        notify(err, vim.log.levels.WARN)
        return nil
    end
    if mode == nil or mode == '' then return info.mode end
    if mode ~= 'off' and mode ~= 'ask' and mode ~= 'coach' then
        notify('Mode must be off, ask, or coach', vim.log.levels.ERROR)
        return nil
    end
    set_mode_for_root(info.root, mode)
    logger.event('mode_changed', { root_id = root_key(info.root):sub(1, 12), mode = mode })
    for _, target in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(target) then
            local target_info = project_info(target)
            if target_info and target_info.root == info.root then
                vim.b[target].c_tutor_mode = mode
                if mode == 'off' then
                    clear_buffer(target, 'Tutor mode disabled')
                else
                    activate_buffer(target)
                end
            end
        end
    end
    if mode == 'coach' then
        notify 'Coach mode enabled: only explicit // tutor:, // coach:, // t:, and // c: questions are sent through OMP.'
    else
        notify(('Tutor mode: %s'):format(mode))
    end
    return mode
end

function M.toggle()
    local mode = M.mode()
    if not mode then return end
    local next_mode = mode == 'ask' and 'coach' or (mode == 'coach' and 'off' or 'ask')
    return M.mode(next_mode)
end

function M.status()
    local bufnr = vim.api.nvim_get_current_buf()
    local info, err = project_info(bufnr)
    if not info then
        notify(('Unavailable: %s'):format(err), vim.log.levels.INFO)
        return
    end
    local log_status = logger.last_error() and ('error:' .. logger.last_error()) or (logger.path() or 'unavailable')
    notify(
        ('mode=%s · backend=%s/%s · active=%s · pending=%d · annotations=%d · cached=%d · log=%s'):format(
            info.mode,
            state.client.backend,
            state.client:status(),
            state.active and 'yes' or 'no',
            #state.queue,
            vim.tbl_count(state.annotations[bufnr] or {}),
            vim.tbl_count(state.cache),
            log_status
        )
    )
end

function M.statusline()
    local mode = vim.b.c_tutor_mode
    return mode and ('Tutor:' .. mode) or ''
end

local MAX_TUTOR_PROJECT_STATE_BYTES = 4 * 1024 * 1024

local function reference_timestamp() return os.date '!%Y-%m-%dT%H:%M:%SZ' end

local function project_reference_state(info)
    local path = info.root .. '/.tutor/state.json'
    local document, read_error = read_json(path, MAX_TUTOR_PROJECT_STATE_BYTES)
    if not document then return nil, path, ('Tutor project state is unavailable: %s'):format(read_error or 'missing') end
    if type(document.kcs) ~= 'table' then return nil, path, 'Tutor project state has an invalid knowledge-component table' end
    if document.references == nil then document.references = {} end
    if type(document.references) ~= 'table' then return nil, path, 'Tutor project state has an invalid reference table' end
    return document, path
end

local function reference_command(action)
    local bufnr = vim.api.nvim_get_current_buf()
    local last = response_at_line(bufnr, vim.api.nvim_win_get_cursor(0)[1]) or state.last_response[bufnr]
    if not last then
        notify('No tutor response is available as a reference', vim.log.levels.INFO)
        return false
    end
    local info, err = project_info(bufnr)
    if not info then
        notify(err, vim.log.levels.WARN)
        return false
    end
    local topic = last.response.concept:lower():gsub('[^%w_.%-]', '-')
    local prefix = info.profile.concept_prefix
    if not topic:match('^' .. vim.pesc(prefix) .. '%.') then topic = prefix .. '.' .. topic end

    local document, path, state_error = project_reference_state(info)
    if not document then
        notify(state_error, vim.log.levels.ERROR)
        return false
    end
    local reference = document.references[topic]
    if reference ~= nil and type(reference) ~= 'table' then
        notify('Tutor project reference has an invalid record', vim.log.levels.ERROR)
        return false
    end

    local now = reference_timestamp()
    if action == 'add' then
        if not reference then
            reference = { created = now, uses = 0, last_used = vim.NIL, history = {} }
            document.references[topic] = reference
        end
        if type(reference.history) ~= 'table' or type(reference.uses) ~= 'number' then
            notify('Tutor project reference has invalid history', vim.log.levels.ERROR)
            return false
        end
        reference.summary = (last.response.title .. ': ' .. last.response.explanation):sub(1, 500)
        reference.location = ('%s:%d'):format(info.relative_path, render.position(bufnr, last.mark_id) or last.response.anchor_line)
        reference.history[#reference.history + 1] = { t = now, event = 'add' }
    else
        if not reference then
            notify('Tutor reference must be saved before recording its use', vim.log.levels.INFO)
            return false
        end
        if type(reference.history) ~= 'table' or type(reference.uses) ~= 'number' then
            notify('Tutor project reference has invalid history', vim.log.levels.ERROR)
            return false
        end
        reference.uses = reference.uses + 1
        reference.last_used = now
        reference.history[#reference.history + 1] = { t = now, event = 'use' }
    end

    if not write_json(path, document, 'reference_persisted', 'reference_write_failed') then
        notify('Tutor reference state could not be written', vim.log.levels.ERROR)
        return false
    end
    notify(action == 'add' and 'Tutor reference saved' or 'Tutor reference use recorded')
    return true
end

function M.remember() return reference_command 'add' end
function M.record_reference_use() return reference_command 'use' end

function M.setup(opts)
    if state.setup then return end
    state.setup = true
    config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    local log_ok, log_error = logger.setup {
        path = config.log_path or (config.state_dir .. '/events.jsonl'),
        max_bytes = config.log_max_bytes,
    }
    if not log_ok then notify(('Tutor event logging unavailable: %s'):format(log_error), vim.log.levels.WARN) end
    logger.event('tutor_setup', { model = config.model, backend = config.command and 'omp' or config.backend })
    load_state()
    load_cache()
    render.setup()
    state.client = rpc.new {
        backend = config.command and 'omp' or config.backend,
        command = config.command,
        curl_command = config.curl_command,
        cwd = config.rpc_cwd,
        model = config.model,
        endpoint = config.endpoint,
        api_key_env = config.api_key_env,
        service_tier = config.service_tier,
        thinking_level = config.thinking_level,
        timeout_ms = config.request_timeout_ms,
        on_status = function(value)
            state.client_status = value
            logger.event('rpc_status', { backend = state.client and state.client.backend or config.backend, status = value })
        end,
    }

    local group = vim.api.nvim_create_augroup('Tutor', { clear = true })
    vim.api.nvim_create_autocmd('BufEnter', {
        group = group,
        pattern = languages.patterns,
        callback = function(event) reconcile_eligibility(event.buf) end,
    })
    vim.api.nvim_create_autocmd({ 'BufFilePost', 'FileType' }, {
        group = group,
        callback = function(event) reconcile_eligibility(event.buf) end,
    })
    vim.api.nvim_create_autocmd('InsertEnter', {
        group = group,
        pattern = languages.patterns,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            cancel_buffer_work(event.buf, 'Tutor work cancelled on InsertEnter')
        end,
    })
    vim.api.nvim_create_autocmd('InsertLeave', {
        group = group,
        pattern = languages.patterns,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            schedule_current_marker(event.buf, config.ask_debounce_ms, event.event)
        end,
    })
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = group,
        pattern = languages.patterns,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            if reconcile_eligibility(event.buf, 'Tutor project eligibility changed') then
                schedule_current_marker(event.buf, config.ask_debounce_ms, event.event)
            end
        end,
    })
    vim.api.nvim_create_autocmd('TextChanged', {
        group = group,
        pattern = languages.patterns,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            invalidate(event.buf)
            schedule_current_marker(event.buf, config.ask_debounce_ms, event.event)
        end,
    })
    vim.api.nvim_create_autocmd('TextChangedI', {
        group = group,
        pattern = languages.patterns,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            invalidate(event.buf)
            -- Insert-mode edits only reconcile permanent decorations. InsertLeave starts new work.
        end,
    })
    vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
        group = group,
        callback = function(event)
            log_editor_event(event.event, event.buf)
            clear_buffer(event.buf, 'Tutor buffer closed')
            state.projects[event.buf] = nil
        end,
    })
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = function()
            state.client:stop()
            logger.stop()
        end,
    })

    activate_buffer(vim.api.nvim_get_current_buf())

    vim.api.nvim_create_user_command('CTutorAsk', M.ask_current, {})
    vim.api.nvim_create_user_command('CTutorExplain', M.explain_diagnostic, {})
    vim.api.nvim_create_user_command('CTutorMore', M.more, {})
    vim.api.nvim_create_user_command('CTutorReroll', M.reroll, {})
    vim.api.nvim_create_user_command('CTutorDismiss', M.dismiss, {})
    vim.api.nvim_create_user_command('CTutorToggle', M.toggle, {})
    vim.api.nvim_create_user_command('CTutorStatus', M.status, {})
    vim.api.nvim_create_user_command('CTutorLog', function() notify(('Tutor log: %s'):format(logger.path() or 'unavailable')) end, {})
    vim.api.nvim_create_user_command('CTutorRemember', M.remember, {})
    vim.api.nvim_create_user_command('CTutorUse', M.record_reference_use, {})
    vim.api.nvim_create_user_command('CTutorMode', function(command) M.mode(command.args) end, {
        nargs = '?',
        complete = function() return { 'off', 'ask', 'coach' } end,
    })
end

M._test = {
    marker_question = marker_question,
    project_info = project_info,
    source_context = source_context,
    request_for = request_for,
    anticipate_buffer = anticipate_buffer,
    annotation_at = annotation_at,
    restore_cached_annotations = restore_cached_annotations,
    invalidate = invalidate,
    cache_path = cache_path,
    save_cache = save_cache,
    marker_cache_key = marker_cache_key,
    cache_profile = cache_profile,
    logger = logger,
    state = state,
}

return M
