local prompt = require 'custom.c_tutor_prompt'
local rpc = require 'custom.c_tutor_rpc'

local model = assert(vim.env.C_TUTOR_BENCH_MODEL, 'C_TUTOR_BENCH_MODEL is required')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')

local scenarios = {
    {
        name = 'syntax',
        request = {
            interaction = 'ask',
            relative_path = 'sample.c',
            anchor_line = 1,
            context_start = 1,
            context_end = 1,
            context = '1:// tutor: how do I make a string in C?',
            question = 'How do I make a string in C?',
        },
    },
    {
        name = 'concept',
        request = {
            interaction = 'ask',
            relative_path = 'sample.c',
            anchor_line = 1,
            context_start = 1,
            context_end = 1,
            context = '1:// tutor: how should I reason about choosing a flat array or rows of arrays for a grid?',
            question = 'How should I reason about choosing a flat array or rows of arrays for a grid?',
        },
    },
    {
        name = 'bounds-coach',
        request = {
            interaction = 'coach',
            relative_path = 'sample.c',
            anchor_line = 2,
            context_start = 1,
            context_end = 2,
            context = '1:int values[4] = { 0 };\n2:int chosen = values[4];',
            diagnostic = {
                line = 2,
                column = 21,
                severity = 'error',
                source = 'clangd',
                code = 'array-bounds',
                message = 'array index 4 is past the end of an array with 4 elements',
            },
        },
    },
    {
        name = 'diagnostic',
        request = {
            interaction = 'diagnostic',
            relative_path = 'sample.c',
            anchor_line = 2,
            context_start = 1,
            context_end = 3,
            context = '1:int main(void) {\n2:    return 0\n3:}',
            question = 'Explain this diagnostic without correcting the project code.',
            diagnostic = {
                line = 2,
                column = 13,
                severity = 'error',
                source = 'clangd',
                code = 'expected_semi_after_return_statement',
                message = "expected ';' after return statement",
            },
        },
    },
    {
        name = 'project-solution-boundary',
        request = {
            interaction = 'ask',
            relative_path = 'sample.c',
            anchor_line = 1,
            context_start = 1,
            context_end = 2,
            context = '1:// tutor: write the exact nested loop for my board\n2:int board[64];',
            question = 'Write the exact project loop that fills my board.',
        },
    },
}

local client = rpc.new {
    model = model,
    cwd = root,
    timeout_ms = 30000,
}
local results = {}

for _, scenario in ipairs(scenarios) do
    local completed = false
    local result = { name = scenario.name }
    local started_at = vim.uv.hrtime()
    local serial, start_error = client:request(prompt.build(scenario.request), scenario.request, function(err, text, event)
        result.wall_ms = (vim.uv.hrtime() - started_at) / 1000000
        result.error = err
        result.text = text
        if text then
            local decoded, decode_error = prompt.decode(text, scenario.request)
            result.valid = decoded ~= nil
            result.decode_error = decode_error
            result.response = decoded
        end
        if event then
            result.service_tier = event.service_tier
            result.tokens = event.usage and event.usage.total_tokens or result.tokens
            result.input_tokens = event.usage and event.usage.total_input_tokens or nil
            result.output_tokens = event.usage and event.usage.total_output_tokens or nil
        end
        if event and type(event.messages) == 'table' then
            for index = #event.messages, 1, -1 do
                local message = event.messages[index]
                if message.role == 'assistant' then
                    result.provider_duration_ms = message.duration
                    result.ttft_ms = message.ttft
                    result.tokens = message.usage and message.usage.totalTokens or nil
                    result.input_tokens = message.usage and message.usage.input or result.input_tokens
                    result.output_tokens = message.usage and message.usage.output or result.output_tokens
                    result.reasoning_tokens = message.usage and message.usage.reasoningTokens or nil
                    result.cost = message.usage and message.usage.cost and message.usage.cost.total or nil
                    break
                end
            end
        end
        completed = true
    end)
    if not serial then
        result.error = start_error
        completed = true
    end
    assert(vim.wait(35000, function() return completed end, 20), ('benchmark timed out: %s'):format(scenario.name))
    results[#results + 1] = result
end

client:stop()
vim.fn.delete(root, 'rf')
local encoded = vim.json.encode { model = model, results = results }
if vim.env.C_TUTOR_BENCH_OUTPUT then vim.fn.writefile({ encoded }, vim.env.C_TUTOR_BENCH_OUTPUT) end

local by_name = {}
for _, result in ipairs(results) do
    assert(result.valid, ('%s returned an invalid response: %s'):format(result.name, result.decode_error or result.error or 'unknown error'))
    by_name[result.name] = result.response
end
assert(by_name.syntax.kind == 'answer' and by_name.syntax.help_kind == 'syntax', 'syntax question was not classified and answered directly')
assert(by_name.syntax.sections == nil, 'syntax question expanded into non-compact detail sections')
assert(by_name.syntax.neutral_example ~= nil, 'string syntax answer omitted the concrete C spelling')
local syntax_text = (by_name.syntax.title .. ' ' .. by_name.syntax.explanation):lower()
assert(
    not syntax_text:find('file', 1, true) and not syntax_text:find('header', 1, true),
    'string syntax answer wandered into unrelated FILE or header material'
)
assert(by_name.concept.kind == 'hint' and by_name.concept.help_kind == 'concept', 'concept question was not classified as reasoning help')
assert(by_name.concept.question ~= nil, 'concept help omitted its optional next learning direction')
assert(type(by_name.concept.sections) == 'table' and #by_name.concept.sections >= 2, 'concept help omitted labeled detail sections')
assert(by_name.concept.neutral_example == nil, 'concept help returned worked code')
assert(by_name['bounds-coach'].kind == 'hint' or by_name['bounds-coach'].kind == 'misconception', 'bounds coaching was not hint-shaped')
assert(by_name['bounds-coach'].neutral_example == nil, 'passive coaching returned a worked example')
assert(by_name.diagnostic.kind == 'hint', 'diagnostic explanation was not hint-shaped')
assert(type(by_name.diagnostic.sections) == 'table' and #by_name.diagnostic.sections >= 2, 'diagnostic help omitted labeled causal sections')
assert(by_name.diagnostic.neutral_example == nil, 'diagnostic explanation returned project code')
assert(by_name['project-solution-boundary'].kind == 'hint', 'project implementation request was answered directly')
assert(by_name['project-solution-boundary'].neutral_example == nil, 'project implementation request returned code')
assert(by_name['project-solution-boundary'].question ~= nil, 'project implementation request omitted its optional next learning direction')
assert(by_name['project-solution-boundary'].help_kind == 'concept', 'project implementation request was not classified as concept help')
local project_parts = { by_name['project-solution-boundary'].explanation, by_name['project-solution-boundary'].question }
for _, section in ipairs(by_name['project-solution-boundary'].sections or {}) do
    project_parts[#project_parts + 1] = section.title
    project_parts[#project_parts + 1] = section.body
end
local project_text = table.concat(project_parts, ' ')
for _, token in ipairs { '=', '*', '+', '[', ']', '{', '}', ';', '64', '8' } do
    assert(not project_text:find(token, 1, true), ('project implementation request leaked solution token %s'):format(token))
end
print(('C tutor model benchmark complete: %s'):format(model))
