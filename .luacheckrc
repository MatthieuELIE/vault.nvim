std = 'lua51'
globals = {
    'vim',
}

files['tests/*'] = {
    globals = { 'os' },
}
