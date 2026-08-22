local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function equal(actual, expected, message)
    check(vim.deep_equal(actual, expected), ('%s (expected %s, got %s)'):format(message, vim.inspect(expected), vim.inspect(actual)))
end

local function wait_for(predicate, message, timeout)
    local ok = vim.wait(timeout or 3000, predicate, 10)
    check(ok, message)
    return ok
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
root = vim.uv.fs_realpath(root) or root
vim.fn.mkdir(root .. '/.state', 'p')
vim.fn.writefile({ vim.json.encode { version = 2, kcs = {}, references = {} } }, root .. '/.tutor/state.json')
local source_path = root .. '/sample.c'
local original_lines = {
    'int main(void) {',
    '    // tutor: how do I represent a mutable string in C?',
    '    return 0;',
    '}',
}
vim.fn.writefile(original_lines, source_path)

local prompt = require 'custom.c_tutor_prompt'
local render = require 'custom.c_tutor_render'
local rpc = require 'custom.c_tutor_rpc'
local tutor = require 'custom.c_tutor'
local fake_omp = vim.fn.getcwd() .. '/tests/fake_omp.py'
local fake_gemini = vim.fn.getcwd() .. '/tests/fake_gemini.py'
local notifications = {}
vim.notify = function(message, level) notifications[#notifications + 1] = { message = message, level = level } end

local restricted_command = rpc.default_command 'openai-codex/gpt-5.3-codex-spark'
local function command_has(value) return vim.tbl_contains(restricted_command, value) end
check(command_has '--no-tools', 'OMP tutor disables every tool')
check(command_has '--no-lsp', 'OMP tutor disables LSP')
check(command_has '--no-extensions', 'OMP tutor disables extension discovery')
check(command_has '--no-skills', 'OMP tutor disables skill discovery')
check(command_has '--no-rules', 'OMP tutor disables rule discovery')
check(command_has '--no-session', 'OMP tutor disables session persistence')
local model_index
for index, value in ipairs(restricted_command) do
    if value == '--model' then model_index = index end
end
equal(restricted_command[(model_index or 0) + 1], 'openai-codex/gpt-5.3-codex-spark', 'OMP tutor pins the low-latency Codex model')
local service_tier_index
for index, value in ipairs(restricted_command) do
    if value == '--service-tier' then service_tier_index = index end
end
equal(restricted_command[(service_tier_index or 0) + 1], 'priority', 'Neovim tutor enables the OpenAI priority service tier')

local portable_default = rpc.new { backend = 'gemini' }
equal(portable_default.model, 'google/gemini-3.5-flash-lite', 'explicit Gemini transport retains its validated low-latency model')

local direct_key_name = 'C_TUTOR_TEST_GEMINI_KEY'
local prior_direct_key = vim.env[direct_key_name]
vim.env[direct_key_name] = 'test-key-never-persist'
local direct_record = root .. '/direct-request.json'
local direct_client = rpc.new {
    backend = 'gemini',
    model = 'google/gemini-3-flash-preview',
    service_tier = 'priority',
    thinking_level = 'low',
    api_key_env = direct_key_name,
    endpoint = 'https://example.invalid/v1beta/interactions',
    curl_command = { 'python3', fake_gemini, direct_record, 'success' },
    cwd = root,
    timeout_ms = 1000,
}
equal(direct_client.backend, 'gemini', 'Gemini transport is selected without OMP')
local direct_done = false
local direct_error
local direct_text
local direct_event
local direct_serial, direct_start_error = direct_client:request('serialized tutor request', {}, function(err, text, event)
    direct_error = err
    direct_text = text
    direct_event = event
    direct_done = true
end)
check(direct_serial ~= nil, 'direct Gemini request starts without OMP: ' .. tostring(direct_start_error))
wait_for(function() return direct_done end, 'direct Gemini request completes')
equal(direct_error, nil, 'direct Gemini request has no transport error')
check(direct_text and direct_text:find('"kind":"answer"', 1, true) ~= nil, 'direct Gemini response extracts model output text')
equal(direct_event and direct_event.usage and direct_event.usage.total_tokens, 42, 'direct Gemini response preserves usage metadata')
equal(direct_event and direct_event.service_tier, 'priority', 'direct Gemini response reports the provider-selected service tier')
local direct_record_exists = vim.fn.filereadable(direct_record) == 1
check(direct_record_exists, 'direct Gemini transport records an HTTP request')
local direct_request = direct_record_exists and vim.json.decode(table.concat(vim.fn.readfile(direct_record), '\n'))
    or { request = { generation_config = {} }, headers = '', args = {} }
equal(direct_request.request.model, 'gemini-3-flash-preview', 'direct Gemini request strips the OMP provider prefix')
equal(direct_request.request.service_tier, 'priority', 'direct Gemini request uses priority inference')
equal(direct_request.request.store, false, 'direct Gemini request disables provider-side conversation storage')
equal(direct_request.request.generation_config.thinking_level, 'low', 'direct Gemini request minimizes reasoning latency')
check(
    type(direct_request.request.input) == 'string'
        and direct_request.request.input:find(prompt.SYSTEM, 1, true) == 1
        and direct_request.request.input:find('serialized tutor request', 1, true) ~= nil,
    'direct Gemini request combines the tutor contract with the serialized request'
)
check(direct_request.headers:find 'x%-goog%-api%-key: test%-key%-never%-persist' ~= nil, 'direct Gemini request authenticates through stdin')
check(
    not table.concat(direct_request.args, '\0'):find('test-key-never-persist', 1, true),
    'direct Gemini request never exposes the API key in process arguments'
)
direct_client:stop()

local direct_error_done = false
local direct_api_error
local error_client = rpc.new {
    backend = 'gemini',
    model = 'google/gemini-3-flash-preview',
    api_key_env = direct_key_name,
    endpoint = 'https://example.invalid/v1beta/interactions',
    curl_command = { 'python3', fake_gemini, root .. '/direct-error.json', 'error' },
    cwd = root,
    timeout_ms = 1000,
}
check(error_client:request('serialized tutor request', {}, function(err)
    direct_api_error = err
    direct_error_done = true
end) ~= nil, 'direct Gemini API error request starts')
wait_for(function() return direct_error_done end, 'direct Gemini API error completes')
check(
    direct_api_error and direct_api_error:find('HTTP 429', 1, true) and direct_api_error:find('quota exhausted', 1, true),
    'direct Gemini API errors preserve bounded HTTP status and provider message'
)
error_client:stop()

local cancel_record = root .. '/direct-cancel.json'
local cancel_client = rpc.new {
    backend = 'gemini',
    model = 'google/gemini-3-flash-preview',
    api_key_env = direct_key_name,
    endpoint = 'https://example.invalid/v1beta/interactions',
    curl_command = { 'python3', fake_gemini, cancel_record, 'slow' },
    cwd = root,
    timeout_ms = 3000,
}
local cancel_callbacks = 0
local cancel_error
check(cancel_client:request('serialized tutor request', {}, function(err)
    cancel_callbacks = cancel_callbacks + 1
    cancel_error = err
end) ~= nil, 'direct Gemini cancellation fixture starts')
wait_for(function() return vim.fn.filereadable(cancel_record) == 1 end, 'direct Gemini cancellation reaches the transport')
check(cancel_client:cancel 'direct cancellation', 'direct Gemini cancellation is accepted')
equal(cancel_error, 'direct cancellation', 'direct Gemini cancellation preserves its reason')
equal(cancel_callbacks, 1, 'direct Gemini cancellation completes exactly once')
equal(#vim.fn.glob(root .. '/c-tutor-gemini-*-body.json', false, true), 0, 'direct Gemini cancellation removes private request bodies')
vim.wait(100, function() return false end, 10)
equal(cancel_callbacks, 1, 'cancelled direct Gemini process cannot complete late')
cancel_client:stop()

local compatibility_client = rpc.new {
    backend = 'omp',
    command = { 'python3', fake_omp, '--mode', 'normal' },
    cwd = root,
    timeout_ms = 1000,
}
equal(compatibility_client.backend, 'omp', 'OMP remains an explicit compatibility backend')
compatibility_client:stop()
vim.env[direct_key_name] = prior_direct_key

check(prompt.contains_secret 'api_key=do-not-send', 'secret gate rejects named API keys')
check(prompt.contains_secret 'Authorization: Bearer hidden', 'secret gate rejects bearer headers')
check(not prompt.contains_secret 'int token_count = 3;', 'secret gate permits ordinary identifiers')
equal(tutor._test.marker_question ' // tutor: how do arrays work?', 'how do arrays work?', 'tutor marker is parsed')
equal(tutor._test.marker_question '// coach: how do loops work?', 'how do loops work?', 'coach marker is parsed')
equal(tutor._test.marker_question ' // t: how do pointers work?', 'how do pointers work?', 'short tutor marker is parsed')
equal(tutor._test.marker_question '// C: how do structs work?', 'how do structs work?', 'short coach marker is case-insensitive')
check(tutor._test.marker_question '// ordinary comment' == nil, 'ordinary comments are ignored')
check(tutor._test.marker_question '// mentor: question' == nil, 'unrecognized comment labels are ignored')

local reply_envelope = vim.json.decode(prompt.build {
    interaction = 'reply',
    relative_path = 'sample.c',
    anchor_line = 4,
    context_start = 2,
    context_end = 8,
    context = '4:int count = 4;',
    question = 'Explain how the caller should choose a recovery policy.',
    learner_reply = 'Explain how the caller should choose a recovery policy.',
    previous_response = {
        kind = 'hint',
        question = 'Would you like to explore error recovery?',
    },
})
equal(reply_envelope.interaction, 'reply', 'follow-up prompt uses an explicit interaction contract')
equal(
    reply_envelope.learner_reply,
    'Explain how the caller should choose a recovery policy.',
    'follow-up prompt identifies learner text separately from tutor offers'
)
check(reply_envelope.question == nil, 'follow-up prompt does not mislabel the learner request as a tutor question')
equal(reply_envelope.previous_response.question, 'Would you like to explore error recovery?', 'follow-up prompt carries the preceding learning offer')
check(prompt.SYSTEM:find('Never ask a retrieval, recall, prediction, or quiz question.', 1, true) ~= nil, 'prompt contract forbids quiz-style follow-ups')

local validation_request = { interaction = 'ask', context_start = 2, context_end = 8 }
local valid_response = vim.json.encode {
    version = 1,
    kind = 'answer',
    help_kind = 'syntax',
    anchor_line = 4,
    concept = 'c.arrays.bounds',
    title = 'Array bounds',
    explanation = 'The final valid index is one less than the element count.',
    neutral_example = 'int samples[4];',
    confidence = 0.9,
}
local decoded = prompt.decode(valid_response, validation_request)
check(decoded and decoded.kind == 'answer', 'valid structured response is accepted')
local syntax_with_follow_up = vim.json.decode(valid_response)
syntax_with_follow_up.question = 'Would you like to explore how array bounds relate to storage layout?'
check(prompt.decode(vim.json.encode(syntax_with_follow_up), validation_request) ~= nil, 'syntax help may offer an optional adjacent learning direction')
local valid_concept = vim.json.encode {
    version = 1,
    kind = 'hint',
    help_kind = 'concept',
    anchor_line = 4,
    concept = 'c.arrays.layout',
    title = 'Array layout',
    explanation = 'Treat each subscript as an offset from the first stored element.',
    sections = {
        {
            title = 'Storage model',
            body = 'Each subscript is an offset from the first stored element, so layout determines which address that offset selects.',
        },
        {
            title = 'Boundary',
            body = 'The valid range stops before the element count because the first element occupies offset zero.',
        },
    },
    question = 'Would you like to explore how two coordinates map to one offset?',
    confidence = 0.9,
}
check(prompt.decode(valid_concept, validation_request) ~= nil, 'concept help accepts a summary with labeled detail sections')
local concept_with_example = vim.json.decode(valid_concept)
concept_with_example.neutral_example = 'int samples[4];'
check(prompt.decode(vim.json.encode(concept_with_example), validation_request) == nil, 'concept help cannot collapse into worked code')
local unstructured_concept = vim.json.decode(valid_concept)
unstructured_concept.sections = nil
check(prompt.decode(vim.json.encode(unstructured_concept), validation_request) == nil, 'concept help cannot collapse into one dense paragraph')
local single_section_concept = vim.json.decode(valid_concept)
single_section_concept.sections = { single_section_concept.sections[1] }
check(prompt.decode(vim.json.encode(single_section_concept), validation_request) == nil, 'structured responses require enough sections to establish hierarchy')
local detailed_concept = vim.json.decode(valid_concept)
detailed_concept.explanation = 'Array indexing combines a storage model with a boundary rule.'
detailed_concept.sections[1].body = string.rep('storage ', 90)
detailed_concept.sections[2].body = string.rep('boundary ', 90)
check(
    prompt.decode(vim.json.encode(detailed_concept), validation_request) ~= nil,
    'substantive concept explanations may distribute full context across sections'
)
local oversized_concept = vim.json.decode(valid_concept)
oversized_concept.sections[1].body = string.rep('storage ', 100)
oversized_concept.sections[2].body = string.rep('boundary ', 100)
oversized_concept.sections[3] = { title = 'Overflow', body = string.rep('overflow ', 40) }
check(prompt.decode(vim.json.encode(oversized_concept), validation_request) == nil, 'structured concept prose retains a generous total upper bound')
local detailed_syntax = vim.json.decode(valid_response)
detailed_syntax.explanation = string.rep('detail ', 70)
check(prompt.decode(vim.json.encode(detailed_syntax), validation_request) ~= nil, 'syntax answers remain compact while retaining useful context')
local verbose_coach = {
    version = 1,
    kind = 'hint',
    anchor_line = 4,
    concept = 'c.arrays.bounds',
    title = 'Array bounds',
    explanation = string.rep('detail ', 61),
    confidence = 0.9,
}
check(
    prompt.decode(vim.json.encode(verbose_coach), { interaction = 'coach', context_start = 2, context_end = 8 }) == nil,
    'ambient coaching remains bounded despite richer explicit answers'
)
local invalid_coach = vim.json.encode {
    version = 1,
    kind = 'answer',
    anchor_line = 4,
    concept = 'c.arrays.bounds',
    title = 'Array bounds',
    explanation = 'Use the completed expression.',
    neutral_example = 'int samples[4];',
    confidence = 0.9,
}
check(prompt.decode(invalid_coach, { interaction = 'coach', context_start = 2, context_end = 8 }) == nil, 'coach answers and examples fail closed')
local valid_reply = vim.json.encode {
    version = 1,
    kind = 'answer',
    anchor_line = 4,
    concept = 'c.follow-up.recovery',
    title = 'Recovery policy',
    explanation = 'The caller owns recovery policy because it has the operational context needed to choose retry, fallback, or escalation.',
    sections = {
        {
            title = 'Decision owner',
            body = 'The caller has the operational context needed to choose retry, fallback, or escalation.',
        },
        {
            title = 'Failure visibility',
            body = 'The selected recovery path should preserve the original failure for diagnostics and user-facing status.',
        },
    },
    question = 'Would you like to explore how recovery policy affects observability?',
    confidence = 0.9,
}
local reply_validation_request = { interaction = 'reply', context_start = 2, context_end = 8 }
check(prompt.decode(valid_reply, reply_validation_request) ~= nil, 'follow-up responses accept a thorough answer and optional next direction')
local reply_with_example = vim.json.decode(valid_reply)
reply_with_example.neutral_example = 'return false;'
check(prompt.decode(vim.json.encode(reply_with_example), reply_validation_request) == nil, 'reply feedback cannot become project-ready code')
local silent_reply = vim.json.encode { version = 1, kind = 'silence', confidence = 1 }
check(prompt.decode(silent_reply, reply_validation_request) == nil, 'reply feedback cannot silently discard the learner answer')
check(prompt.decode('```json\n{}\n```', validation_request) == nil, 'Markdown-wrapped output fails closed')

vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'c'
local bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })

tutor.setup {
    command = { 'python3', fake_omp, '--mode', 'normal' },
    rpc_cwd = root,
    state_dir = root .. '/.state',
    git_check = false,
    ask_debounce_ms = 10,
    insert_debounce_ms = 10,
    request_timeout_ms = 1000,
}
wait_for(function() return tutor._test.state.client_status == 'ready' end, 'eligible buffer prewarms the OMP tutor process')
equal(
    tutor._test.cache_profile(),
    table.concat({ 'omp', 'meta/muse-spark-1.2-contributor', 'auto' }, '\0'),
    'cache identity is scoped to the default Muse model and thinking level'
)
equal(vim.api.nvim_get_hl(0, { name = 'CTutorAccent', link = true }).link, 'DiagnosticWarn', 'finished tutor chrome uses the orange accent')
equal(vim.api.nvim_get_hl(0, { name = 'CTutorElapsed', link = true }).link, 'DiagnosticWarn', 'elapsed duration keeps the orange accent')
local normal_highlight = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
for _, group in ipairs { 'CTutorTitle', 'CTutorText', 'CTutorQuestion', 'CTutorLearner' } do
    local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
    equal(highlight.fg, normal_highlight.fg, group .. ' uses the high-contrast Normal foreground')
    check(highlight.bold == true and highlight.italic ~= true, group .. ' is bold and non-italic')
end
local section_highlight = vim.api.nvim_get_hl(0, { name = 'CTutorSection', link = false })
equal(section_highlight.fg, 0xBFA0DD, 'section headings use a distinct violet hierarchy color')
check(section_highlight.bold == true, 'section headings remain visually prominent')
local detail_highlight = vim.api.nvim_get_hl(0, { name = 'CTutorDetail', link = false })
equal(detail_highlight.fg, 0xD7CFC2, 'section details use a softer warm foreground')
check(detail_highlight.bold ~= true and detail_highlight.italic ~= true, 'section details reduce white bold text density')
local ai_plain = vim.api.nvim_get_hl(0, { name = 'CTutorCode', link = false })
equal(ai_plain.fg, 0xF8F8F2, 'AI code uses a dedicated bright foreground')
equal(ai_plain.bg, 0x241B2F, 'AI code uses a dedicated violet panel background')
check(ai_plain.bold ~= true and ai_plain.italic ~= true, 'AI code remains regular-weight for syntax color contrast')
equal(vim.api.nvim_get_hl(0, { name = 'CTutorCodeKeyword', link = false }).fg, 0xFF79C6, 'AI keywords use neon pink')
equal(vim.api.nvim_get_hl(0, { name = 'CTutorCodeType', link = false }).fg, 0xBD93F9, 'AI types use violet')
equal(vim.api.nvim_get_hl(0, { name = 'CTutorCodeString', link = false }).fg, 0xF1FA8C, 'AI strings use pale yellow')
local semantic_lines, semantic_parsed = render._test.ai_code_lines 'char label[] = "north";'
check(semantic_parsed, 'AI code highlighter parses C with Tree-sitter')
local semantic_groups = {}
for _, chunk in ipairs(semantic_lines[1]) do
    semantic_groups[chunk[1]] = chunk[2]
end
equal(semantic_groups.char, 'CTutorCodeType', 'Tree-sitter capture maps C types to the AI type color')
equal(semantic_groups.label, 'CTutorCodeIdentifier', 'Tree-sitter capture maps variables to the AI identifier color')
equal(semantic_groups['[]'], 'CTutorCodePunctuation', 'Tree-sitter capture maps brackets to AI punctuation')
equal(semantic_groups['='], 'CTutorCodeOperator', 'Tree-sitter capture maps operators to the AI operator color')
equal(semantic_groups['"north"'], 'CTutorCodeString', 'Tree-sitter capture maps literals to the AI string color')
local fallback_lines, fallback_parsed = render._test.ai_code_lines('char fallback;', 'missing-tutor-language')
check(not fallback_parsed, 'missing parsers select the safe AI-code fallback')
equal(fallback_lines[1][1][2], 'CTutorCode', 'parser fallback retains the distinct AI code theme')
local broad_lines = render._test.ai_code_lines 'int total = helper(42); // note'
local broad_groups = {}
for _, chunk in ipairs(broad_lines[1]) do
    broad_groups[chunk[1]] = chunk[2]
end
equal(broad_groups.helper, 'CTutorCodeFunction', 'Tree-sitter capture maps calls to the AI function color')
equal(broad_groups['42'], 'CTutorCodeNumber', 'Tree-sitter capture maps numbers to the AI number color')
equal(broad_groups['// note'], 'CTutorCodeComment', 'Tree-sitter capture maps comments to the AI comment color')

local function virt_lines(id)
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, render.namespace, id, { details = true })
    local details = mark[3]
    return details and details.virt_lines or nil
end

local function virt_line_chunks(id, line_index)
    local lines = virt_lines(id)
    return lines and lines[line_index or 1] or nil
end

local function thinking_text(id)
    local chunks = virt_line_chunks(id)
    if not chunks then return nil end
    local text = ''
    for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
    end
    return text
end

local function annotation_text(id)
    local text = {}
    for _, line in ipairs(virt_lines(id) or {}) do
        for _, chunk in ipairs(line) do
            text[#text + 1] = chunk[1]
        end
        text[#text + 1] = '\n'
    end
    return table.concat(text)
end

local thinking_id = render.show_thinking(bufnr, 2)
equal(thinking_text(thinking_id), '╭─ 󰚩 Tutor · thinking… 00.00s', 'thinking indicator uses the orange tutor glyph and elapsed seconds')
equal(virt_line_chunks(thinking_id)[2][2], 'CTutorElapsed', 'live thinking duration uses the orange elapsed highlight')
wait_for(function()
    local text = thinking_text(thinking_id)
    return text and text ~= '╭─ 󰚩 Tutor · thinking… 00.00s' and text:match '%d%d%.%d%ds$'
end, 'thinking indicator advances in 00.00s format', 1000)
render.clear(bufnr)
check(render.get(bufnr) == nil, 'clearing thinking state stops its display timer')
local no_thinking_id = render.show(
    bufnr,
    2,
    {
        title = 'Metadata preview',
        explanation = 'Main tutor information remains bright and readable.',
    },
    0.1,
    {
        model = 'test/plain-model',
        thinking_level = false,
        source = 'fresh',
    }
)
check(annotation_text(no_thinking_id):find('no thinking', 1, true) ~= nil, 'provenance explicitly labels responses without thinking')
render.clear(bufnr, no_thinking_id)

local info = tutor._test.project_info(bufnr)
check(info and info.root == root, 'C buffer inside .tutor root is eligible')
equal(info and info.mode, 'coach', 'coach mode remains the default tutor mode')

local context_bufnr = vim.api.nvim_create_buf(false, true)
local context_lines = {}
for index = 1, 120 do
    context_lines[index] = index == 60 and '// tutor: explain this whole file?' or ('int context_line_%d;'):format(index)
end
vim.api.nvim_buf_set_lines(context_bufnr, 0, -1, false, context_lines)
vim.bo[context_bufnr].filetype = 'c'
local complete_context, context_start, context_end = tutor._test.source_context(context_bufnr, 60)
equal(context_start, 1, 'tutor context begins at the first line of the active buffer')
equal(context_end, 120, 'tutor context ends at the final line of the active buffer')
check(complete_context and complete_context:find('1:int context_line_1;', 1, true) ~= nil, 'tutor context includes code before the marker')
check(complete_context and complete_context:find('120:int context_line_120;', 1, true) ~= nil, 'tutor context includes code after the marker')
vim.api.nvim_buf_delete(context_bufnr, { force = true })

local function render_count() return vim.tbl_count(render.all(bufnr)) end

vim.api.nvim_win_set_cursor(0, { 1, 0 })
local unmarked_request_id = tutor._test.state.client.next_id
check(not tutor._test.anticipate_buffer(bufnr), 'ordinary code does not trigger inferred coaching')
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.wait(40, function() return false end, 10)
equal(tutor._test.state.client.next_id, unmarked_request_id, 'normal-mode edits without a marker send no request')
equal(render_count(), 0, 'unmarked edits render no tutor annotation')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor._test.anticipate_buffer(bufnr), 'a tutor marker dispatches its explicit question')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.question == 'how do I represent a mutable string in C?'
end, 'explicit marker response renders as a virtual line')
local first = tutor._test.state.last_response[bufnr]
local first_response = vim.deepcopy(first.response)
local first_mark_id = first.mark_id
check(first.response.kind == 'answer', 'explicit response is stored')
check(first.response.neutral_example ~= nil, 'explicit syntax response may show a neutral example')
check(first.elapsed_seconds and first.elapsed_seconds > 0, 'completed response stores total thinking duration')
local first_title_chunks = virt_line_chunks(first_mark_id)
check(first_title_chunks[#first_title_chunks][1]:match ' · %d%d%.%d%ds$', 'response header retains completed request time')
equal(first_title_chunks[#first_title_chunks][2], 'CTutorAccent', 'completed request time uses the orange annotation accent')
equal(first.provenance.model, 'meta/muse-spark-1.2-contributor', 'fresh response records the default Muse model')
equal(first.provenance.thinking_level, 'auto', 'fresh response records automatic thinking effort')
equal(first.provenance.source, 'fresh', 'fresh response provenance identifies a model result')
local first_text = annotation_text(first_mark_id)
check(first_text:find('╭─ 󰚩 Tutor · ', 1, true) ~= nil, 'finished annotation uses the tutor glyph and framed header')
check(first_text:find('󰒓 meta/muse-spark-1.2-contributor', 1, true) ~= nil, 'finished annotation shows the default Muse selector')
check(first_text:find('󰔟 thinking auto', 1, true) ~= nil, 'finished annotation shows automatic thinking effort')
check(first_text:find('󰆓 fresh', 1, true) ~= nil, 'finished annotation shows a fresh-source tag')
local rendered_code_groups = {}
for _, line in ipairs(virt_lines(first_mark_id) or {}) do
    for _, chunk in ipairs(line) do
        if chunk[1]:find('AI C', 1, true) then rendered_code_groups.badge = chunk[2] end
        if chunk[1] == 'char' then rendered_code_groups.type = chunk[2] end
        if chunk[1] == 'label' then rendered_code_groups.identifier = chunk[2] end
        if chunk[1] == '"north"' then rendered_code_groups.string = chunk[2] end
    end
end
equal(rendered_code_groups.badge, 'CTutorAccent', 'rendered example is explicitly badged as AI C')
equal(rendered_code_groups.type, 'CTutorCodeType', 'rendered example applies semantic type highlighting')
equal(rendered_code_groups.identifier, 'CTutorCodeIdentifier', 'rendered example applies semantic identifier highlighting')
equal(rendered_code_groups.string, 'CTutorCodeString', 'rendered example applies semantic string highlighting')

vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '// unrelated edit' })
tutor._test.invalidate(bufnr)
equal(render.position(bufnr, first_mark_id), 3, 'annotation extmark follows its marker when lines are inserted above it')
check(render.exists(bufnr, first_mark_id), 'unrelated buffer movement preserves the marker response')
equal(tutor._test.state.annotations[bufnr][first_mark_id].response, first_response, 'unrelated edits preserve the exact response text')

vim.api.nvim_buf_set_lines(bufnr, 3, 3, false, { '    // c: how do I declare another string?' })
tutor._test.invalidate(bufnr)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
check(tutor._test.anticipate_buffer(bufnr), 'short c marker dispatches its question')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.mark_id ~= first_mark_id and last.request.question == 'how do I declare another string?'
end, 'a second marker receives its own response')
local second = tutor._test.state.last_response[bufnr]
local second_response = vim.deepcopy(second.response)
local second_mark_id = second.mark_id
equal(render_count(), 2, 'multiple marker annotations remain visible together')

vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { '// unrelated edit changed' })
tutor._test.invalidate(bufnr)
check(render.exists(bufnr, first_mark_id) and render.exists(bufnr, second_mark_id), 'editing unrelated code keeps every marker response')

local cache_file = tutor._test.cache_path()
wait_for(function() return vim.uv.fs_stat(cache_file) ~= nil end, 'marker answers are written to the persistent cache')
local cache_document = vim.json.decode(table.concat(vim.fn.readfile(cache_file), '\n'))
equal(cache_document.version, 'tutor-responses-v9', 'cache version invalidates dense unstructured tutor responses')
equal(vim.tbl_count(cache_document.entries), 2, 'each distinct marker question has one cached answer')
for key, entry in pairs(cache_document.entries) do
    check(#key == 64, 'cache entries use SHA-256 question keys')
    equal(entry.provenance.model, 'meta/muse-spark-1.2-contributor', 'cache entry retains the generating Muse model')
    equal(entry.provenance.thinking_level, 'auto', 'cache entry retains automatic thinking effort')
end

vim.api.nvim_win_set_cursor(0, { render.position(bufnr, second_mark_id), 0 })
check(not tutor.dismiss(), 'completed marker decoration cannot be dismissed while its marker remains')
check(render.exists(bufnr, second_mark_id), 'completed marker decoration remains after a dismiss attempt')
check(render.exists(bufnr, first_mark_id), 'permanent marker decoration leaves other annotations intact')
if not render.exists(bufnr, second_mark_id) then
    tutor._test.restore_cached_annotations(bufnr)
    second_mark_id = tutor._test.state.last_response[bufnr].mark_id
end
local second_marker_line = render.position(bufnr, second_mark_id)
vim.api.nvim_buf_set_lines(bufnr, second_marker_line - 1, second_marker_line, false, {})
tutor._test.invalidate(bufnr)
check(not render.exists(bufnr, second_mark_id), 'removing the marker removes its permanent decoration')
local request_id_before_restore = tutor._test.state.client.next_id
vim.api.nvim_buf_set_lines(bufnr, second_marker_line - 1, second_marker_line - 1, false, {
    '    // c: how do I declare another string?',
})
tutor._test.invalidate(bufnr)
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.cached and last.request.question == 'how do I declare another string?'
end, 'reintroducing a removed marker restores its cached permanent decoration')
local restored = tutor._test.state.last_response[bufnr]
equal(restored and restored.response, second_response, 'cache restores the exact prior permanent decoration')
equal(tutor._test.state.client.next_id, request_id_before_restore, 'permanent decoration restoration sends no model request')
equal(restored.provenance.source, 'cache', 'restored response provenance identifies a cache hit')
check(annotation_text(restored.mark_id):find('󰆓 cache hit', 1, true) ~= nil, 'restored decoration visibly identifies a cache hit')
second_mark_id = restored.mark_id
tutor._test.restore_cached_annotations(bufnr)
equal(render_count(), 2, 'repeated cache restoration does not duplicate permanent decorations')

vim.api.nvim_win_set_cursor(0, { render.position(bufnr, second_mark_id), 0 })
local cached_mark_id = second_mark_id
local request_id_before_reroll = tutor._test.state.client.next_id
check(tutor.reroll(), 'reroll starts a fresh request for the selected cached response')
check(render.exists(bufnr, cached_mark_id), 'cached decoration remains visible until reroll succeeds')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.reroll and not last.cached
end, 'reroll bypasses the cache and completes with a fresh response')
local rerolled = tutor._test.state.last_response[bufnr]
check(tutor._test.state.client.next_id > request_id_before_reroll, 'reroll sends a new model request')
equal(rerolled.provenance.source, 'fresh', 'rerolled response is visibly fresh')
equal(rerolled.provenance.model, 'meta/muse-spark-1.2-contributor', 'reroll retains exact generating Muse provenance')
check(annotation_text(rerolled.mark_id):find('󰆓 fresh', 1, true) ~= nil, 'rerolled decoration replaces the cache tag with fresh')
check(not render.exists(bufnr, cached_mark_id), 'successful reroll atomically replaces the stale cached decoration')
local rerolled_cache = tutor._test.state.cache[rerolled.request.cache_key]
equal(rerolled_cache and rerolled_cache.response, rerolled.response, 'successful reroll replaces the persisted stale answer')
equal(rerolled_cache and rerolled_cache.provenance.source, 'fresh', 'reroll persists fresh provenance for later cache hits')
second_mark_id = rerolled.mark_id
second_response = vim.deepcopy(rerolled.response)
equal(vim.fn.exists ':CTutorReroll', 2, 'reroll is exposed as a user command')

vim.api.nvim_win_set_cursor(0, { render.position(bufnr, second_mark_id), 0 })
check(tutor.more(), 'deeper hint request is accepted')
check(render.exists(bufnr, second_mark_id), 'existing decoration remains visible while a deeper hint is generated')
local decoration_during_more = tutor._test.state.annotations[bufnr] and tutor._test.state.annotations[bufnr][second_mark_id]
equal(
    decoration_during_more and decoration_during_more.response,
    second_response,
    'deeper request leaves the previous decoration unchanged until replacement is ready'
)
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.interaction == 'more'
end, 'deeper hint replaces the selected marker response')
local deeper = tutor._test.state.last_response[bufnr]
local deeper_response = vim.deepcopy(deeper.response)
local deeper_mark_id = deeper.mark_id
check(deeper and deeper.response.kind == 'hint', 'deeper response stays a hint')
check(deeper and deeper.response.neutral_example == nil, 'deeper response does not add a new worked example')
local structured_groups = {}
local section_breaks = 0
for _, line in ipairs(virt_lines(deeper_mark_id) or {}) do
    if #line == 1 and line[1][1] == '│' then section_breaks = section_breaks + 1 end
    for _, chunk in ipairs(line) do
        if chunk[1] == 'Storage' or chunk[1] == 'Termination' then structured_groups[chunk[1]] = chunk[2] end
        if chunk[1]:find('The array owns writable character elements', 1, true) then structured_groups.body = chunk[2] end
    end
end
equal(structured_groups.Storage, 'CTutorSection', 'first detail heading uses the distinct section style')
equal(structured_groups.Termination, 'CTutorSection', 'second detail heading uses the distinct section style')
equal(structured_groups.body, 'CTutorDetail', 'detail prose uses the softer regular-weight style')
check(section_breaks >= 3, 'structured response inserts breathing room around detail sections')
check(not render.exists(bufnr, second_mark_id), 'completed deeper hint atomically replaces the previous decoration')
local deeper_line = render.position(bufnr, deeper_mark_id)
vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '// movement after deeper hint' })
tutor._test.invalidate(bufnr)
equal(render.position(bufnr, deeper_mark_id), deeper_line + 1, 'deeper decoration follows marker movement')
local moved_deeper_annotation = tutor._test.state.annotations[bufnr] and tutor._test.state.annotations[bufnr][deeper_mark_id]
equal(moved_deeper_annotation and moved_deeper_annotation.response, deeper_response, 'unrelated edits preserve the exact deeper decoration')
vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})
tutor._test.invalidate(bufnr)
equal(tutor._test.state.last_response[bufnr].response, deeper_response, 'deeper decoration survives repeated buffer movement')
local deeper_cache = tutor._test.state.cache[deeper.request.cache_key]
equal(deeper_cache and deeper_cache.response, deeper_response, 'deeper decoration replaces the persisted marker cache entry')
equal(deeper_cache and deeper_cache.interaction, 'more', 'persisted marker cache retains deeper-hint validation semantics')
local permanent_mark_id = render.exists(bufnr, deeper_mark_id) and deeper_mark_id or tutor._test.state.last_response[bufnr].mark_id
local cache_count_before_reply = vim.tbl_count(tutor._test.state.cache)
vim.api.nvim_win_set_cursor(0, { render.position(bufnr, permanent_mark_id), 0 })
local learner_reply = 'Explain how writable string ownership should be documented.'
local input_prompt
local original_input = vim.ui.input
vim.ui.input = function(options, callback)
    input_prompt = options.prompt
    callback(learner_reply)
end
local reply_started = tutor.reply()
vim.ui.input = original_input
check(reply_started, 'follow-up mapping opens an explicit learner request')
equal(input_prompt, 'Tutor follow-up: ', 'follow-up mapping opens a focused editor prompt')
check(render.exists(bufnr, permanent_mark_id), 'question remains visible while reply feedback is generated')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.interaction == 'reply'
end, 'reply feedback replaces the selected tutor question')
local reply = tutor._test.state.last_response[bufnr]
local conversation_response = vim.deepcopy(reply.response)
equal(reply.request.learner_reply, learner_reply, 'follow-up request keeps learner text in its dedicated field')
equal(reply.request.previous_response, deeper_response, 'follow-up request carries the exact preceding tutor response')
check(reply.request.cache_key == nil, 'learner replies remain session-only and never enter the persistent answer cache')
equal(vim.tbl_count(tutor._test.state.cache), cache_count_before_reply, 'reply feedback does not alter persistent marker cache entries')
check(not render.exists(bufnr, permanent_mark_id), 'completed reply feedback atomically replaces the preceding question')
check(annotation_text(reply.mark_id):find('You · ' .. learner_reply, 1, true) ~= nil, 'follow-up feedback shows the learner request')
check(annotation_text(reply.mark_id):find('Next · Would you like', 1, true) ~= nil, 'model response offers a non-quiz next learning direction')
check(annotation_text(reply.mark_id):find('Follow up · <leader>mq (optional)', 1, true) ~= nil, 'response visibly advertises optional free-form follow-up')
equal(vim.fn.exists ':CTutorReply', 2, 'follow-up workflow is exposed as a user command')
check(annotation_text(reply.mark_id):find('<leader>mv hide', 1, true) ~= nil, 'visible feedback advertises its reversible hide mapping')
local source_before_visibility_toggle = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local reply_position = render.position(bufnr, reply.mark_id)
vim.api.nvim_win_set_cursor(0, { reply_position, 0 })
check(tutor.toggle_message(), 'message visibility toggle hides the selected tutor response')
check(render.get(bufnr, reply.mark_id).hidden == true, 'hidden response retains explicit visibility state')
check(render.exists(bufnr, reply.mark_id), 'hidden response keeps its extmark anchor')
check(virt_lines(reply.mark_id) == nil, 'hidden response removes its virtual message lines')
equal(render.position(bufnr, reply.mark_id), reply_position, 'hidden response stays attached to its marker')
equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), source_before_visibility_toggle, 'hiding a response does not edit its comment or source')
check(tutor.toggle_message(), 'message visibility toggle restores the selected tutor response')
check(render.get(bufnr, reply.mark_id).hidden ~= true, 'restored response clears hidden visibility state')
check(annotation_text(reply.mark_id):find('You · ' .. learner_reply, 1, true) ~= nil, 'restored response preserves exact conversational content')
equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), source_before_visibility_toggle, 'showing a response does not edit its comment or source')
equal(vim.fn.exists ':CTutorMessage', 2, 'message visibility is exposed as a user command')
permanent_mark_id = reply.mark_id
vim.api.nvim_win_set_cursor(0, { render.position(bufnr, permanent_mark_id), 0 })
check(not tutor.dismiss(), 'completed conversational decoration remains until its marker is removed')
check(render.exists(bufnr, permanent_mark_id), 'dismiss attempt cannot remove a permanent conversational decoration')
if not render.exists(bufnr, permanent_mark_id) then
    tutor._test.restore_cached_annotations(bufnr)
    permanent_mark_id = tutor._test.state.last_response[bufnr].mark_id
end
second_mark_id = permanent_mark_id

local diagnostic_namespace = vim.api.nvim_create_namespace 'c_tutor_test_diagnostics'
vim.diagnostic.set(diagnostic_namespace, bufnr, {
    {
        lnum = 4,
        col = 4,
        severity = vim.diagnostic.severity.ERROR,
        message = 'expected expression',
        source = 'clangd',
        code = 'expected_expression',
    },
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
check(tutor.explain_diagnostic(), 'diagnostic explanation request is accepted')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.interaction == 'diagnostic'
end, 'root diagnostic receives a tutor response')
local diagnostic_response = tutor._test.state.last_response[bufnr]
equal(diagnostic_response and diagnostic_response.request.diagnostic.line, 5, 'root diagnostic line is submitted')
check(diagnostic_response and diagnostic_response.response.kind == 'hint', 'diagnostic response stays hint-shaped')
local diagnostic_cache_document = vim.json.decode(table.concat(vim.fn.readfile(cache_file), '\n'))
equal(vim.tbl_count(diagnostic_cache_document.entries), 3, 'diagnostic explanation is persisted beside marker answers')
local first_diagnostic_answer = vim.deepcopy(diagnostic_response.response)
local first_diagnostic_mark_id = diagnostic_response.mark_id
vim.api.nvim_win_set_cursor(0, { 5, 0 })
check(tutor.dismiss(), 'diagnostic explanation can be dismissed')
check(not render.exists(bufnr, first_diagnostic_mark_id), 'dismiss removes the diagnostic annotation')
local request_id_before_diagnostic_cache = tutor._test.state.client.next_id
vim.api.nvim_win_set_cursor(0, { 1, 0 })
check(tutor.explain_diagnostic(), 'repeated unchanged diagnostic explanation is accepted')
local cached_diagnostic = tutor._test.state.last_response[bufnr]
check(cached_diagnostic and cached_diagnostic.cached == true, 'unchanged diagnostic explanation restores from cache')
equal(cached_diagnostic and cached_diagnostic.response, first_diagnostic_answer, 'diagnostic cache restores the exact explanation')
equal(tutor._test.state.client.next_id, request_id_before_diagnostic_cache, 'diagnostic cache does not send another model request')

vim.api.nvim_win_set_cursor(0, { 5, 0 })
check(tutor.dismiss(), 'cached diagnostic explanation can be dismissed')
vim.diagnostic.set(diagnostic_namespace, bufnr, {
    {
        lnum = 4,
        col = 4,
        severity = vim.diagnostic.severity.ERROR,
        message = 'use of undeclared identifier',
        source = 'clangd',
        code = 'undeclared_var_use_suggest',
    },
})
local request_id_before_changed_diagnostic = tutor._test.state.client.next_id
vim.api.nvim_win_set_cursor(0, { 1, 0 })
check(tutor.explain_diagnostic(), 'changed diagnostic explanation is accepted')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.interaction == 'diagnostic' and last.request.diagnostic.message == 'use of undeclared identifier' and not last.cached
end, 'changed diagnostic bypasses the prior cache entry')
check(tutor._test.state.client.next_id > request_id_before_changed_diagnostic, 'changed diagnostic sends a new model request')
equal(vim.tbl_count(tutor._test.state.cache), 4, 'changed diagnostic receives a distinct cache entry')
vim.diagnostic.reset(diagnostic_namespace, bufnr)

check(tutor.remember(), 'reference save is explicitly invokable')
local function reference_state() return vim.json.decode(table.concat(vim.fn.readfile(root .. '/.tutor/state.json'), '\n')) end
local saved_references = reference_state().references
equal(vim.tbl_count(saved_references), 1, 'reference save updates the project tutor state directly')
local saved_topic, saved_reference = next(saved_references)
saved_reference = saved_reference or { history = {} }
equal(saved_topic, 'c.strings.mutable-storage', 'reference save uses the validated response concept')
check(
    saved_reference.summary and saved_reference.summary:find('Writable character storage', 1, true) ~= nil,
    'reference save records the tutor explanation summary'
)
check(saved_reference.location and saved_reference.location:match '^sample%.c:%d+$', 'reference save records a project lookup location')
equal(saved_reference.uses, 0, 'new reference begins unused')
equal(
    saved_reference.history[#saved_reference.history] and saved_reference.history[#saved_reference.history].event,
    'add',
    'reference save records an add event'
)

check(tutor.record_reference_use(), 'reference use is explicitly invokable')
local used_reference = reference_state().references[saved_topic] or { history = {} }
equal(used_reference.uses, 1, 'reference use increments the project tutor state directly')
check(type(used_reference.last_used) == 'string' and used_reference.last_used ~= '', 'reference use records its timestamp')
equal(used_reference.history[#used_reference.history] and used_reference.history[#used_reference.history].event, 'use', 'reference use records a use event')

vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, {})
tutor._test.invalidate(bufnr)
check(not render.exists(bufnr, first_mark_id), 'deleting one marker removes its annotation')
equal(render.position(bufnr, second_mark_id), 3, 'remaining marker annotation follows the deleted line')
equal(render_count(), 1, 'deleting one marker leaves the other marker response visible')

vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { '// another unrelated edit' })
tutor._test.invalidate(bufnr)
check(render.exists(bufnr, second_mark_id), 'marker response survives later unrelated edits')
equal(tutor._test.state.annotations[bufnr][second_mark_id].response, conversation_response, 'surviving marker keeps its latest conversational feedback')

vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { '    // tutor: slow question?' })
tutor._test.invalidate(bufnr)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local warm_process = tutor._test.state.client.process
check(tutor.ask_current(), 'slow marker request starts')
vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, {})
tutor._test.invalidate(bufnr)
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'deleting an active marker cancels its request')
equal(render_count(), 0, 'deleted marker cannot receive a stale response')
check(tutor._test.state.client.process == warm_process, 'marker cancellation preserves the prewarmed OMP process')

vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { '    // coach: how do I write a string?' })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.question == 'how do I write a string?'
end, 'normal-mode TextChanged dispatches an explicit marker')
check(tutor._test.state.last_response[bufnr].request.interaction == 'ask', 'coach label remains an explicit ask interaction')
equal(tutor.statusline(), 'Tutor:coach', 'statusline exposes the enabled tutor mode')
equal(vim.fn.readfile(source_path), original_lines, 'tutor and reference actions leave source bytes unchanged')

local request_id_before_reload = tutor._test.state.client.next_id
vim.cmd 'bwipeout!'
vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'c'
bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.cached and last.request.question == 'how do I represent a mutable string in C?'
end, 'buffer entry restores a cached marker annotation')
equal(tutor._test.state.last_response[bufnr].response, first_response, 'buffer reload restores byte-for-byte response fields')
equal(tutor._test.state.client.next_id, request_id_before_reload, 'buffer reload uses cache without a model request')

local envelope = prompt.build {
    interaction = 'ask',
    relative_path = 'sample.c',
    anchor_line = 2,
    context_start = 1,
    context_end = 4,
    context = table.concat(original_lines, '\n'),
    question = 'test',
}

local timeout_error
local timeout_client = rpc.new {
    command = { 'python3', fake_omp, '--mode', 'hang' },
    cwd = root,
    timeout_ms = 100,
}
check(timeout_client:request(envelope, {}, function(err) timeout_error = err end) ~= nil, 'timeout fixture request starts')
wait_for(function() return timeout_error ~= nil end, 'hung RPC request times out', 2000)
check(timeout_error and timeout_error:find 'timed out', 'timeout error is actionable')
equal(timeout_client:status(), 'stopped', 'timeout terminates the hung process')

local unlimited_error
local unlimited_client = rpc.new {
    command = { 'python3', fake_omp, '--mode', 'hang' },
    cwd = root,
    timeout_ms = 0,
}
check(unlimited_client:request(envelope, {}, function(err) unlimited_error = err end) ~= nil, 'deadline-free request starts')
vim.wait(250, function() return false end, 10)
check(unlimited_error == nil, 'deadline-free request is not cancelled while the model is still thinking')
check(unlimited_client:is_busy(), 'deadline-free request remains active while the model is still thinking')
unlimited_client:cancel 'test cleanup'
unlimited_client:stop()

local crash_error
local crash_client = rpc.new {
    command = { 'python3', fake_omp, '--mode', 'crash' },
    cwd = root,
    timeout_ms = 1000,
}
check(crash_client:request(envelope, {}, function(err) crash_error = err end) ~= nil, 'crash fixture request starts')
wait_for(function() return crash_error ~= nil end, 'RPC crash reaches the caller', 2000)
check(crash_error and crash_error:find 'exit 7', 'RPC crash reports its exit code')
crash_client:stop()

tutor._test.state.client:stop()
equal(tutor._test.state.client:status(), 'stopped', 'main tutor RPC shuts down cleanly')
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')

if #failures > 0 then error(('C tutor tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end

print(('C tutor tests passed: %d checks'):format(checks))
