return {
    'lukas-reineke/virt-column.nvim',
    config = function()
        require('virt-column').setup {
            char = '│',
            virtcolumn = '101, 121',
        }
    end,
}
