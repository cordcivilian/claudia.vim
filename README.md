# claudia.vim

Interact with Anthropic's API directly in Vim. Send text and get streaming responses right where you're typing.

## Why

- It's the age of the [terminal](https://github.com/ghostty-org/ghostty).
- AIs don’t need breaks--say no to "message limits."
- Keep API keys out of the browser.
- Maximum AI, minimal config.
- Pay for intelligence, not the messenger.

## Credit

This project is a vim rewrite of the following projects:
- https://github.com/yacineMTB/dingllm.nvim
- https://github.com/melbaldove/llm.nvim

## Features

- Direct integration with Anthropic API
- Streaming responses
- Normal mode and Visual mode
- Cancel responses with Escape key
- Supports Claude 3 models
- WIP: Context caching for efficient API usage

## Usage (with default mappings)

1. Normal Mode:
   - Type your prompt
   - Press `<Leader>c` to send everything from the start of the document to the cursor

2. Visual Mode:
   - Select text (using v, V, or Ctrl-V)
   - Press `<Leader>c` to send only the selected text

3. To cancel a response:
   - Press `Esc` while claudia is responding

## Requirements

- Vim 8+ (for job control features)
- curl installed on your system
- Anthropic API key

## Installation

### vim-plug
```vim
Plug 'cordcivilian/claudia.vim'
```
### Manual Installation
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/cordcivilian/claudia.vim.git
```
## API Key Setup
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```
## Configuration

### Load Time (default configs and mappings shown)
```vim
" Normal mode - uses text from start (of buffer) to cursor
nmap <silent> <Leader>c <Plug>ClaudiaTrigger

" Visual mode - uses selected text
xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual

" API configurations
let g:claudia_user_config = {
    \ 'url': 'https://api.anthropic.com/v1/messages',
    \ 'api_key_name': 'ANTHROPIC_API_KEY',
    \ 'model': 'claude-3-5-sonnet-20241022',
    \ 'system_prompt': 'You are a helpful assistant.',
    \ 'max_tokens': 4096,
    \ 'temperature': 0.25,
    \ }
```
### Runtime
```vim
" Modify configs at runtime
:ClaudiaModel claude-3-opus-20240229
:ClaudiaSystemPrompt Pretend you are sentient.
:ClaudiaTokens 8192
:ClaudiaTemp 0.75
:ClaudiaResetConfig
:ClaudiaShowConfig
```
## License

MIT License
