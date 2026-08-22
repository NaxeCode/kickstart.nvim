local M = {}

local profiles = {
    c = {
        id = 'c',
        display = 'C',
        protocol = 'c-tutor/v1',
        standard = 'c99',
        parser = 'c',
        concept_prefix = 'c',
        filetypes = { c = true },
        extensions = { c = true, h = true },
        patterns = { '*.c', '*.h' },
    },
    swift = {
        id = 'swift',
        display = 'Swift',
        protocol = 'swift-tutor/v1',
        standard = 'swift6',
        parser = 'swift',
        concept_prefix = 'swift',
        filetypes = { swift = true },
        extensions = { swift = true },
        patterns = { '*.swift' },
    },
}

local by_filetype = {}
local patterns = {}
for _, profile in pairs(profiles) do
    for filetype in pairs(profile.filetypes) do
        by_filetype[filetype] = profile
    end
    vim.list_extend(patterns, profile.patterns)
end

function M.parsers()
    local result = {}
    local seen = {}
    for _, profile in pairs(profiles) do
        if not seen[profile.parser] then
            result[#result + 1] = profile.parser
            seen[profile.parser] = true
        end
    end
    table.sort(result)
    return result
end
table.sort(patterns)
M.patterns = patterns

function M.for_buffer(filetype, path)
    local profile = by_filetype[filetype]
    if not profile then return nil, ('unsupported tutor filetype: %s'):format(filetype == '' and '<none>' or filetype) end
    local extension = path:match '%.([^.]+)$'
    if not extension or not profile.extensions[extension:lower()] then return nil, ('unsupported %s source path'):format(profile.display) end
    return profile
end

function M.default() return profiles.c end

return M
