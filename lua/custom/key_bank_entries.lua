-- Active bindings only. Keep at most eight entries across all sections.
return {
    {
        title = 'DEBUGGER · CURRENT FOCUS',
        items = {
            { action = 'Toggle breakpoint', chord = 'LOWER + V', sends = 'F9' },
            { action = 'Start / continue', chord = 'LOWER + G', sends = 'F5' },
            { action = 'Step over', chord = 'LOWER + B', sends = 'F10' },
            { action = 'Terminate debugger', chord = 'LOWER + C', sends = 'F8' },
        },
    },
    {
        title = 'BUILD',
        items = {
            { action = 'Release binary size', chord = 'SPACE M Z', sends = '<leader>mz' },
        },
    },
    {
        title = 'PROJECT',
        items = {
            { action = 'Yazi bottom / right', chord = 'SPACE _ / SPACE |', sends = '<leader>_ / <leader>|' },
            { action = 'Focus split', chord = 'CTRL + H / J / K / L', sends = '<C-h/j/k/l>' },
            { action = 'Close focused split', chord = 'SPACE Q C', sends = '<leader>qc' },
        },
    },
}
