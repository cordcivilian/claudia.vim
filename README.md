# claudia.vim

Interact with Anthropic's API directly in Vim.
Send text and get streaming responses right where you're typing.

## Why

- Alt-Tab? Cmd-Tab? Spaces? No. Stay in the terminal.
- AIs don’t need breaks--say no to "message limits." (ok, maybe [rate limits](https://docs.anthropic.com/en/api/rate-limits))
- Keep API keys out of the browser.
- More AI, less configs.
- Pay for intelligence, not the messenger.
- ["Take Control. Take control of your Cursor. This. This is the instrument of your liberation."](https://www.youtube.com/watch?v=XMjB2jjfw8w&t=157s)

## Credit

This project is a vim rewrite of the following projects:
- https://github.com/yacineMTB/dingllm.nvim
- https://github.com/melbaldove/llm.nvim

## Features

- Direct integration with Anthropic API (Claude 3 models)
- Provide context via file contents [Supported: texts, images, PDFs]
- Normal mode and Visual mode prompting
- Streaming responses
- Stop responses with Escape key
- Customizable API configurations
- Context caching for fast and efficient API usage
- Show exact tokens of current context
- WIP: Knowledge stack (prepend only relevant parts of context)

## Usage (with default mappings)

**1. Normal Mode:**
- Press `<Leader>c` to send everything from the start of the document to the cursor

**2. Visual Mode:**
- Select text (using v, V, or Ctrl-V)
- Press `<Leader>c` to send only the selected text

**3. To cancel a response:**
- Press `Esc` while claudia is responding

## Adding Context

You can add file contents as context that will be prepended to every prompt:

1. Add context files:
```vim
:ClaudiaAddContext ~/path/to/context.txt    " Add a file as context
:ClaudiaAddContext $HOME/pdfs/context.pdf   " Environment variables work
:ClaudiaAddContext ./path/to/context.png    " Relative paths work
```
2. Manage context:
```vim
:ClaudiaShowContext         " List all context files and their IDs
:ClaudiaRemoveContext 6     " Remove context with ID 6
:ClaudiaClearContext        " Remove all context files
:ClaudiaCacheContext 9      " Cache context with ID 9 to avoid reloading
:ClaudiaUncacheContext 9    " Remove context ID 9 from cache
:ClaudiaClearCache          " Clear all cached context
```
Context persists across queries but resets when Vim restarts.  Uncached context
are read fresh on each query, so edits to context files take effect
immediately. Cached context are read and stored in memory (and [prompt
cached](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching).)
Avoid caching frequently edited files since changes won't be reflected until
re-cached.

## System Prompt

claudia uses a system prompt to define its core behavior and capabilities. The
system prompt is loaded from a `system.md` file in the plugin directory and is
automatically cached by the API for improved performance.

## Configuration
1. Create a `system.md` file in the plugin directory:

## Token Counting

Claude limits the total number of input tokens per request. You can check token
counts for different parts of your input using these commands:
```vim
:ClaudiaContextCost " Shows token count for all loaded context files (excluding prompts)
:ClaudiaNormalCost  " Shows token count for text from start of file to cursor (excluding context)
:ClaudiaVisualCost  " Shows token count for current visual selection (excluding context)
```
Use these commands to help you stay within token limits and manage context
effectively.

## Requirements

- Vim 8+ (for job control features)
- curl installed on your system with SSL support
- Anthropic API key (stored in ANTHROPIC_API_KEY environment variable)
- +job and +channel features compiled in Vim
- +json feature compiled in Vim (for JSON handling)

## Getting Started

### Step 1 Option 1: vim-plug (or your preferred plugin manager)
```vim
Plug 'cordcivilian/claudia.vim'
```
### Step 1 Option 2: Manual Installation
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone https://github.com/cordcivilian/claudia.vim.git
```
### Step 2: API Key Setup
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```
## Configuration

### Load Time (default configs and mappings shown)
```vim
" Normal mode - uses text from start (of buffer) to cursor
nmap <silent> <Leader>c <Plug>ClaudiaTrigger
" This is NOT mapped out of the box if your Normal mode <Leader>c is already in use

" Visual mode - uses selected text
xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual
" This is NOT mapped out of the box if your Visual mode <Leader>c is already in use

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
:ClaudiaSystemPrompt Pretend you are sentient.  " Set system prompt
:ClaudiaSystemPrompt ~/path/to/system.md        " Set system prompt from file
:ClaudiaTokens 8192
:ClaudiaTemp 0.75
:ClaudiaResetConfig
:ClaudiaShowConfig
```
