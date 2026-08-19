-- Active bindings only. Keep at most eight entries across all sections.
return {
    {
        title = 'DEBUGGER · CURRENT FOCUS',
        items = {
            { action = 'Toggle breakpoint', chord = 'LOWER + V', sends = 'F9' },
            { action = 'Conditional breakpoint', chord = 'SPACE D SHIFT+B', sends = '<leader>dB' },
            { action = 'Start / continue', chord = 'LOWER + G', sends = 'F5' },
            { action = 'Step over', chord = 'LOWER + B', sends = 'F10' },
            { action = 'Terminate debugger', chord = 'LOWER + C', sends = 'F8' },
            { action = 'Evaluate under cursor', chord = 'SPACE D E', sends = '<leader>de' },
        },
    },
    {
        title = 'EDITOR',
        items = {
            { action = 'Save all + close Neovim', chord = 'SPACE Q Q', sends = '<leader>qq' },
        },
    },
    {
        title = 'VIM MOTIONS',
        items = {
            { action = 'Search word; repeat matches', chord = '*  then  n / N' },
        },
    },
}
