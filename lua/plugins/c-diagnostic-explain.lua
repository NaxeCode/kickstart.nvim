return {
    'piersolenski/wtf.nvim',
    ft = 'c',
    dependencies = {
        'nvim-lua/plenary.nvim',
        'MunifTanjim/nui.nvim',
    },
    opts = {
        provider = 'ollama',
        providers = {
            ollama = {
                model_id = 'gemma4:26b-a4b-it-q4_K_M',
            },
        },
        popup_type = 'popup',
        language = 'english',
        additional_instructions = table.concat({
            'The user is learning C and writes the code from memory.',
            'Explain the diagnostic in plain language and name the underlying C rule.',
            'Identify whether it is likely the root error or a follow-on error.',
            'End with one targeted question or hint that helps the learner find the correction.',
            'Do not provide replacement code or apply a fix unless the user explicitly asks.',
        }, ' '),
    },
    keys = {
        {
            '<leader>me',
            function() require('wtf').diagnose() end,
            mode = { 'n', 'x' },
            desc = 'C: explain diagnostic (local AI)',
        },
    },
}
