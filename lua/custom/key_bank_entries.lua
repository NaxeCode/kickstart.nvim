-- Active bindings only. Keep at most eight entries across all sections.
return {
    {
        title = 'SPLIT WORKSPACE · CURRENT FOCUS',
        items = {
            { action = 'Browse with Yazi', chord = 'SPACE -', sends = '<leader>-' },
            { action = 'Open file on right', chord = 'SPACE _', sends = '<leader>_' },
            { action = 'Open file below', chord = 'SPACE |', sends = '<leader>|' },
            { action = 'Focus split', chord = 'CTRL H / J / K / L', sends = '<C-h/j/k/l>' },
            { action = 'Narrower / wider', chord = 'ALT H / L', sends = '<M-h/l>' },
            { action = 'Shorter / taller', chord = 'ALT J / K', sends = '<M-j/k>' },
            { action = 'Equalize splits', chord = 'SPACE P =', sends = '<leader>p=' },
            { action = 'Close focused / all', chord = 'SPACE Q C / Q Q', sends = '<leader>qc / qq' },
        },
    },
}
