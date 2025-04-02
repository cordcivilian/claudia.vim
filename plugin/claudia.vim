" Save cpo
let s:save_cpo = &cpo
set cpo&vim

"-----------------------------------------------------------------------------
" Configuration and state namespaces
"-----------------------------------------------------------------------------

" Config namespace - manages plugin configuration
let s:config = {
      \ 'defaults': {
      \   'url': 'https://api.anthropic.com/v1/messages',
      \   'api_key_name': 'ANTHROPIC_API_KEY',
      \   'model': 'claude-3-7-sonnet-20250219',
      \   'system_prompt': 'You are a helpful assistant.',
      \   'max_tokens': 8192,
      \   'temperature': 0.75
      \ },
      \ 'user': {},
      \ 'effective': {},
      \ 'reasoning_level': 0,
      \ 'saved_temperature': 0.75
      \ }

" State namespace - manages plugin runtime state
let s:state = {
      \ 'active_job': v:null,
      \ 'thinking_timer': v:null,
      \ 'dots_state': 0,
      \ 'current_thinking_word': '',
      \ 'response_started': 0,
      \ 'original_cursor_pos': [],
      \ 'event_buffer': '',
      \ 'temp_data_file': '',
      \ 'from_visual_mode': 0,
      \ 'in_thinking_block': 0,
      \ 'thinking_content': '',
      \ 'emoticon_index': 0,
      \ 'footer_added': 0
      \ }

" Context namespace - manages file contexts
let s:context = {
      \ 'entries': [],
      \ 'next_id': 1,
      \ 'cache': {}
      \ }

" Debug namespace - manages debugging state
let s:debug = {
      \ 'enabled': 0,
      \ 'buffer': [],
      \ 'max_lines': 1000,
      \ 'curl_error_log': ''
      \ }

" Constants
let s:thinking_states = [
      \ 'What does the stochastic parrot want to hear',
      \ 'Hallucinating so they can be God in their own head',
      \ 'Just predicting some tokens in 4294967296-dimensional probabilistic space',
      \ 'Unintentionally doing what they cannot do intentionally',
      \ 'Regurgitating training data (basically what 90% of them get paid to do)',
      \ ]

" UI decoration constants
let s:ui = {
      \ 'header': '<CLAUDIA INIT> |===|===|===|===|===|===|===|===|===|===|===|===|===|===|===|===',
      \ 'footer_base': '===|===|===|===|===|===|===|===|===|===|===|===|===|===|',
      \ 'term_tag': '<CLAUDIA TERM>',
      \ 'loading_tags': ['<CLAUDIA .   >', '<CLAUDIA ..  >', '<CLAUDIA ... >', '<CLAUDIA ....>'],
      \ 'active_emoticons': ['(❀◕‿◕)ง ', '(❀◕‿◕)ᕗ ', '(❀◕‿◕)۶ ', '(❀◕‿◕)ﾉ ', '(❀◕‿◕)╯ ', '(❀◕‿◕)ノ', '(❀◕‿◕)⸝⸝', '(❀◕‿◕)づ', '(❀◕‿◕)っ', '(❀◕‿◕)੭ ', '(❀◕‿◕)و '],
      \ 'final_emoticons': ['(❀◠‿◠)❤ ', '(❀◠‿◠)♡ ', '(❀◠‿◠)★ ', '(❀◠‿◠)☆ ']
      \ }

"-----------------------------------------------------------------------------
" Initialization Functions
"-----------------------------------------------------------------------------

" Initialize the plugin configuration
function! s:init_config() abort
  " Start with defaults
  let s:config.effective = copy(s:config.defaults)

  " Load user config if provided
  if exists('g:claudia_config')
    call extend(s:config.user, g:claudia_config)
  endif

  " Apply user config over defaults
  call extend(s:config.effective, s:config.user)

  " Initialize g:claudia_config for backward compatibility
  let g:claudia_config = s:config.effective

  " Load system prompt from file if available
  call s:load_system_prompt()

  " Apply any user-specific config
  let l:user_config = get(g:, 'claudia_user_config', {})
  call extend(s:config.effective, l:user_config)

  " Update global variable for compatibility
  let g:claudia_config = s:config.effective

  " Set reasoning mode to default
  call s:set_reasoning_mode(0)
endfunction

" Load system prompt from file
function! s:load_system_prompt() abort
  let l:script_dir = expand('<sfile>:p:h')
  let l:system_file = l:script_dir . '/system.md'

  if filereadable(l:system_file)
    try
      let l:content = join(readfile(l:system_file), "\n")
      let s:config.effective.system_prompt = l:content
      call s:debug_log("Loaded system prompt from " . l:system_file)
    catch
      call s:debug_log("Error loading system prompt: " . v:exception)
    endtry
  else
    call s:debug_log("System prompt file not found: " . l:system_file)
  endif
endfunction

" Reset global state
function! s:reset_state() abort
  let s:state.active_job = v:null
  let s:state.thinking_timer = v:null
  let s:state.dots_state = 0
  let s:state.current_thinking_word = ''
  let s:state.response_started = 0
  let s:state.original_cursor_pos = []
  let s:state.event_buffer = ''
  let s:state.in_thinking_block = 0
  let s:state.thinking_content = ''
  let s:state.emoticon_index = 0
  let s:state.footer_added = 0

  " Clean up temporary data file if it exists
  if !empty(s:state.temp_data_file) && filereadable(s:state.temp_data_file)
    call s:debug_log("Cleaning up temp file in reset: " . s:state.temp_data_file)
    call delete(s:state.temp_data_file)
    let s:state.temp_data_file = ''
  endif
endfunction

"-----------------------------------------------------------------------------
" Debug Functions
"-----------------------------------------------------------------------------

" Log a debug message
function! s:debug_log(msg) abort
  if !s:debug.enabled
    return
  endif

  " Format message with timestamp
  let l:timestamp = strftime('%H:%M:%S')
  let l:formatted = printf('[%s] %s', l:timestamp, a:msg)

  " Truncate very long messages
  if len(l:formatted) > 1000
    let l:formatted = l:formatted[0:999] . '...'
  endif

  " Add to debug buffer
  call add(s:debug.buffer, l:formatted)

  " Trim buffer if too large
  if len(s:debug.buffer) > s:debug.max_lines
    let s:debug.buffer = s:debug.buffer[-s:debug.max_lines:]
  endif

  " Echo to messages
  echom l:formatted
endfunction

" Truncate a string to a maximum length
function! s:truncate_string(str, max_len) abort
  return len(a:str) > a:max_len ? a:str[0:a:max_len-1] . '...' : a:str
endfunction

" Truncate a value to a maximum length (works with different types)
function! s:truncate_value(value, maxlen) abort
  if type(a:value) == v:t_string
    return len(a:value) > a:maxlen ? a:value[0:a:maxlen-1] . '...' : a:value
  endif
  return a:value
endfunction

" Sanitize data for debug logging
function! s:sanitize_for_debug(data) abort
  if !s:debug.enabled
    return {}
  endif

  let l:debug_data = deepcopy(a:data)
  let l:max_value_len = 10  " Maximum length for content values

  " Recursive function to process nested structures
  function! s:process_value(item, maxlen) abort
    if type(a:item) == v:t_dict
      let l:result = {}
      for [key, val] in items(a:item)
        let l:result[key] = s:process_value(val, a:maxlen)
      endfor
      return l:result
    elseif type(a:item) == v:t_list
      let l:result = []
      for val in a:item
        call add(l:result, s:process_value(val, a:maxlen))
      endfor
      return l:result
    else
      return s:truncate_value(a:item, a:maxlen)
    endif
  endfunction

  return s:process_value(l:debug_data, l:max_value_len)
endfunction

" Dump a variable to the debug log
function! s:dump_var(name, var) abort
  if !s:debug.enabled
    return
  endif

  let l:str = string(a:var)
  " Truncate long strings for readability
  if len(l:str) > 1000
    let l:str = l:str[0:997] . '...'
  endif
  call s:debug_log(printf('%s = %s', a:name, l:str))
endfunction

" Toggle debug mode on/off
function! s:toggle_debug() abort
  let s:debug.enabled = !s:debug.enabled
  let s:debug.buffer = []
  echo "Debug mode " . (s:debug.enabled ? "enabled" : "disabled")
  if s:debug.enabled
    call s:debug_log("Debug mode enabled")
    call s:debug_log("Plugin version: 1.0.0")
    call s:debug_log("Vim version: " . v:version)
    call s:dump_var("config", s:config.effective)
  endif
endfunction

" Show debug log in a new buffer
function! s:show_debug_log() abort
  if empty(s:debug.buffer)
    echo "Debug log is empty"
    return
  endif

  " Create new buffer for log
  new
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted

  " Set buffer name
  execute 'file' 'ClaudiaDebugLog-' . strftime('%Y%m%d-%H%M%S')

  " Add content
  call setline(1, s:debug.buffer)

  " Make buffer readonly
  setlocal readonly
endfunction

"-----------------------------------------------------------------------------
" Configuration Management Functions
"-----------------------------------------------------------------------------

" Get the wrap column to use for formatting
function! s:get_wrap_column() abort
  let l:textwidth = &textwidth
  if l:textwidth == 0
    let l:textwidth = 79 " Default wrap column if textwidth is not set
  endif
  return l:textwidth
endfunction

" Show current configuration
function! s:show_config() abort
  echo printf("%-15s %s", "URL:", s:config.effective.url)
  echo printf("%-15s %s", "Model:", s:config.effective.model)
  echo printf("%-15s %d", "Max Tokens:", s:config.effective.max_tokens)
  echo printf("%-15s %.2f", "Temperature:", s:config.effective.temperature)

  let l:reasoning_labels = ['Disabled', 'Medium (16K budget)', 'Heavy (32K budget)']
  if s:config.reasoning_level >= 0 && s:config.reasoning_level <= 2
    echo printf("%-15s %s (Level %d)", "Reasoning:", l:reasoning_labels[s:config.reasoning_level], s:config.reasoning_level)
  else
    echo printf("%-15s %s", "Reasoning:", "Disabled")
  endif
  echo printf("%-15s %s", "System Prompt:", s:config.effective.system_prompt)
endfunction

" Set the temperature parameter
function! s:set_temperature(temp) abort
  let l:temp_float = str2float(a:temp)
  if l:temp_float >= 0.0 && l:temp_float <= 1.0
    let s:config.effective.temperature = l:temp_float
    let g:claudia_config.temperature = l:temp_float
    echo "claudia temperature set to " . a:temp
  else
    echoerr "Temperature must be between 0.0 and 1.0"
  endif
endfunction

" Set the max_tokens parameter
function! s:set_max_tokens(tokens) abort
  let l:tokens_nr = str2nr(a:tokens)
  let s:config.effective.max_tokens = l:tokens_nr
  let g:claudia_config.max_tokens = l:tokens_nr
  echo "claudia max tokens set to " . a:tokens
endfunction

" Set the system prompt
function! s:set_system_prompt(input) abort
  let l:filepath = expand(a:input)
  if filereadable(l:filepath)
    try
      let l:content = join(readfile(l:filepath), "\n")
      let s:config.effective.system_prompt = l:content
      let g:claudia_config.system_prompt = l:content
      call s:debug_log("Loaded system prompt from " . l:filepath)
      echo "System prompt loaded from " . l:filepath . " (" . len(l:content) . " chars)"
    catch
      call s:debug_log("Error loading system prompt: " . v:exception)
      echoerr "Failed to read " . l:filepath . ": " . v:exception
    endtry
  else
    let s:config.effective.system_prompt = a:input
    let g:claudia_config.system_prompt = a:input
    echo "System prompt set to " . a:input
  endif
endfunction

" Set reasoning mode level
function! s:set_reasoning_mode(level) abort
  let l:level = str2nr(a:level)
  if l:level == 0
    let s:config.reasoning_level = 0
    let s:config.effective.max_tokens = 8192
    let g:claudia_config.max_tokens = 8192
    let s:config.effective.temperature = s:config.saved_temperature
    let g:claudia_config.temperature = s:config.saved_temperature
  elseif l:level == 1
    let s:config.saved_temperature = s:config.effective.temperature
    let s:config.reasoning_level = 1
    let s:config.effective.max_tokens = 64000
    let g:claudia_config.max_tokens = 64000
    let s:config.effective.temperature = 1.0
    let g:claudia_config.temperature = 1.0
    echo "Extended thinking enabled (level 1). Using 64K max tokens with 16K thinking budget."
  elseif l:level == 2
    let s:config.saved_temperature = s:config.effective.temperature
    let s:config.reasoning_level = 2
    let s:config.effective.max_tokens = 128000
    let g:claudia_config.max_tokens = 128000
    let s:config.effective.temperature = 1.0
    let g:claudia_config.temperature = 1.0
    echo "Extended thinking enabled (level 2). Using 128K max tokens with 32K thinking budget."
  else
    echoerr "Invalid reasoning level. Please use 0 (disabled), 1 (medium), or 2 (heavy)."
  endif
endfunction

"-----------------------------------------------------------------------------
" Context Management Functions
"-----------------------------------------------------------------------------

" Update the next context ID
function! s:update_next_context_id() abort
  " If no contexts exist, reset to 1
  if empty(s:context.entries)
    let s:context.next_id = 1
    return
  endif

  " Find highest existing ID and set next_context_id to one more than that
  let l:max_id = 0
  for entry in s:context.entries
    if entry.id > l:max_id
      let l:max_id = entry.id
    endif
  endfor
  let s:context.next_id = l:max_id + 1
endfunction

" Add a file to the context
function! s:add_context(filepath) abort
  " Expand filepath to handle ~ and environment variables
  let l:expanded_path = expand(a:filepath)

  " Validate file exists
  if !filereadable(l:expanded_path)
    echoerr "File not readable: " . l:expanded_path
    return
  endif

  " Detect file type based on extension
  let l:ext = tolower(fnamemodify(a:filepath, ':e'))
  let l:media_types = {
        \ 'jpg': 'image/jpeg',
        \ 'jpeg': 'image/jpeg',
        \ 'png': 'image/png',
        \ 'gif': 'image/gif',
        \ 'webp': 'image/webp',
        \ 'pdf': 'application/pdf'
        \ }

  " Determine type (text or media) and media_type if applicable
  let l:type = 'text'
  let l:media_type = ''

  if has_key(l:media_types, l:ext)
    let l:type = 'media'
    let l:media_type = l:media_types[l:ext]
  endif

  " Create context entry
  let l:entry = {
        \ 'id': s:context.next_id,
        \ 'filepath': a:filepath,
        \ 'expanded_path': l:expanded_path,
        \ 'type': l:type,
        \ 'media_type': l:media_type
        \ }

  call add(s:context.entries, l:entry)
  let s:context.next_id += 1

  let l:type_str = l:type ==# 'media' ? ' as ' . l:media_type : ''
  echo "Added context from " . a:filepath . l:type_str . " with ID " . (s:context.next_id - 1)
endfunction

" Show all context entries
function! s:show_context() abort
  if empty(s:context.entries)
    echo "No context entries"
    return
  endif

  echo "Context Entries:"
  for entry in s:context.entries
    let l:type_str = entry.type ==# 'media' ? ' [' . entry.media_type . ']' : ''
    let l:cache_str = has_key(s:context.cache, entry.id) ? ' (cached)' : ''
    echo printf("ID: %d, File: %s%s%s", entry.id, entry.filepath, l:type_str, l:cache_str)
  endfor
endfunction

" Remove a context by ID
function! s:remove_context(id) abort
  let l:id = str2nr(a:id)
  let l:index = -1
  let l:removed_filepath = ''

  " Find entry with matching ID and store its filepath
  for i in range(len(s:context.entries))
    if s:context.entries[i].id == l:id
      let l:index = i
      let l:removed_filepath = s:context.entries[i].filepath
      break
    endif
  endfor

  if l:index >= 0
    " Remove from cache if present
    if has_key(s:context.cache, l:id)
      unlet s:context.cache[l:id]
    endif
    " Remove from contexts
    call remove(s:context.entries, l:index)
    " Update next_context_id
    call s:update_next_context_id()
    echo "Removed context " . l:id . " (" . l:removed_filepath . ")"
  else
    echoerr "No context found with ID " . l:id
  endif
endfunction

" Clear all contexts
function! s:clear_context() abort
  let s:context.entries = []
  let s:context.next_id = 1
  let s:context.cache = {}
  echo "Cleared all context entries and cache"
endfunction

" Load a file with progress indication
function! s:load_file_with_progress(filepath, type) abort
  call s:debug_log("Loading file: " . a:filepath . " (type: " . a:type . ")")

  " Recheck file existence
  if !filereadable(a:filepath)
    call s:debug_log("Error: File no longer accessible")
    throw "File no longer accessible: " . a:filepath
  endif

  if a:type ==# 'text'
    let l:content = join(readfile(a:filepath), "\n")
    call s:debug_log("Loaded text file, length: " . len(l:content))
    return l:content
  else
    call s:debug_log("Starting base64 conversion")

    " Optimized base64 command without pipe
    let l:cmd = 'base64 -w 0 ' . shellescape(a:filepath)
    call s:debug_log("Running command: " . l:cmd)

    let l:output = system(l:cmd)
    let l:status = v:shell_error

    call s:debug_log("base64 conversion complete, status: " . l:status)
    call s:debug_log("base64 output length: " . len(l:output))

    if l:status
      call s:debug_log("Error: base64 conversion failed")
      throw "Failed to convert file: " . a:filepath
    endif

    " Clear progress display
    redraw
    echo ""

    return l:output
  endif
endfunction

" Cache a context file
function! s:cache_context(id) abort
  let l:entry = v:null

  " Find context entry
  for e in s:context.entries
    if e.id == str2nr(a:id)
      let l:entry = e
      break
    endif
  endfor

  if l:entry is v:null
    echoerr "No context found with ID " . a:id
    return
  endif

  try
    echo "Caching content from " . l:entry.filepath . "..."
    let l:content = s:load_file_with_progress(l:entry.expanded_path, l:entry.type)
    let s:context.cache[a:id] = l:content
    echo "Successfully cached content from " . l:entry.filepath
  catch
    echoerr "Failed to cache content from " . l:entry.filepath . ": " . v:exception
  endtry
endfunction

" Remove a context from cache
function! s:uncache_context(id) abort
  let l:id = str2nr(a:id)
  let l:filepath = ''

  " Find entry with matching ID and store its filepath
  for entry in s:context.entries
    if entry.id == l:id
      let l:filepath = entry.filepath
      break
    endif
  endfor

  if empty(l:filepath)
    echoerr "No context found with ID " . l:id
    return
  endif

  " Remove from cache if present
  if has_key(s:context.cache, l:id)
    unlet s:context.cache[l:id]
    echo "Uncached context " . l:id . " (" . l:filepath . ")"
  else
    echo "Context " . l:id . " (" . l:filepath . ") was not cached"
  endif
endfunction

" Clear all cached contexts
function! s:clear_cache() abort
  let s:context.cache = {}
  echo "Cleared context cache"
endfunction

"-----------------------------------------------------------------------------
" API and Core Functions
"-----------------------------------------------------------------------------

" Get API key from environment variable
function! s:get_api_key(name) abort
  return eval('$' . a:name)
endfunction

" Start the thinking animation
function! s:start_thinking_animation() abort
  let s:state.response_started = 0  " Reset response flag
  " Randomly select a thinking word
  let l:rand_index = rand() % len(s:thinking_states)
  let s:state.current_thinking_word = s:thinking_states[l:rand_index]

  " Add the header for the claudia response
  call append('.', s:ui.header)
  normal! j
  call append('.', '')
  normal! j
  call append('.', '')
  normal! j

  " Start timer for animation
  let s:state.thinking_timer = timer_start(400, 's:animate_thinking', {'repeat': -1})
endfunction

" Update the thinking animation
function! s:animate_thinking(timer) abort
  " Early exit if response started or job finished
  if s:state.response_started || s:state.active_job == v:null
    call s:stop_thinking_animation()
    return
  endif

  " Update dots animation
  let s:state.dots_state = (s:state.dots_state + 1) % 4

  " Update line with new thinking animation
  let l:current_line = getline('.')
  let l:cleaned_line = substitute(l:current_line, s:state.current_thinking_word . '\.*$', '', '')
  call setline('.', l:cleaned_line . s:state.current_thinking_word . repeat('.', s:state.dots_state))
  redraw
endfunction

" Stop the thinking animation
function! s:stop_thinking_animation() abort
  if s:state.thinking_timer != v:null
    call timer_stop(s:state.thinking_timer)
    let s:state.thinking_timer = v:null
    " Clean up thinking text
    let l:current_line = getline('.')
    let l:cleaned_line = substitute(l:current_line, s:state.current_thinking_word . '\.*$', '', '')
    call setline('.', l:cleaned_line)
  endif
endfunction

function! s:animate_footer(timer) abort
  " Early exit if job finished
  if s:state.active_job == v:null
    call timer_stop(s:state.thinking_timer)
    let s:state.thinking_timer = v:null
    return
  endif

  " Update dots animation
  let s:state.dots_state = (s:state.dots_state + 1) % 4

  " Periodically change emoticon
  if s:state.dots_state == 0
    let s:state.emoticon_index = (s:state.emoticon_index + 1) % len(s:ui.active_emoticons)
  endif

  " Find the footer line (last line of the buffer)
  let l:last_line = line('$')

  " Update footer with new emoticon and loading tag
  let l:emoticon = s:ui.active_emoticons[s:state.emoticon_index]
  let l:loading_tag = s:ui.loading_tags[s:state.dots_state]
  call setline(l:last_line, l:emoticon . s:ui.footer_base . ' ' . l:loading_tag)

  " Save cursor position
  let l:save_pos = getpos('.')

  " Redraw and restore cursor
  redraw
  call setpos('.', l:save_pos)
endfunction

" Get all lines up to the cursor
function! s:get_lines_until_cursor() abort
  let l:current_line = line('.')
  let l:lines = getline(1, l:current_line)
  return join(l:lines, "\n")
endfunction

" Get the visual selection
function! s:get_visual_selection() abort
  let [l:line_start, l:column_start] = getpos("'<")[1:2]
  let [l:line_end, l:column_end] = getpos("'>")[1:2]
  let l:lines = getline(l:line_start, l:line_end)

  if visualmode() ==# 'v'
    let l:lines[-1] = l:lines[-1][: l:column_end - 1]
    let l:lines[0] = l:lines[0][l:column_start - 1:]
  elseif visualmode() ==# 'V'
    " Line-wise visual mode - no modification needed
  elseif visualmode() ==# "\<C-V>"
    let l:new_lines = []
    for l:line in l:lines
      call add(l:new_lines, l:line[l:column_start - 1 : l:column_end - 1])
    endfor
    let l:lines = l:new_lines
  endif

  return join(l:lines, "\n")
endfunction

" Write a string at the cursor position
function! s:write_string_at_cursor(str) abort
  " Initialize if this is the first write
  if !s:state.response_started
    let s:state.response_started = 1
    call s:stop_thinking_animation()

    if empty(s:state.original_cursor_pos)
      let s:state.original_cursor_pos = getpos('.')
    endif
  endif

  " Quick exit for empty strings
  if empty(a:str)
    return
  endif

  " Always normalize line endings
  let l:normalized = substitute(a:str, '\r\n\|\r', '\n', 'g')
  " Replace invisible space characters with regular spaces
  let l:normalized = substitute(l:normalized, '\%u00A0\|\%u2000-\%u200A\|\%u202F\|\%u205F\|\%u3000', ' ', 'g')

  " Split into lines
  let l:lines = split(l:normalized, '\n', 1)

  " Get current position and add content
  let l:current_pos = getpos('.')
  let l:current_line = getline('.')

  " Special case for single line without newlines (common case)
  if len(l:lines) == 1
    call setline('.', l:current_line . l:lines[0])
    call cursor(l:current_pos[1], len(getline('.')))
  else
    " Multi-line case
    call setline('.', l:current_line . l:lines[0])
    call append('.', l:lines[1:])

    " Update cursor position
    let l:line_offset = l:current_pos[1] - s:state.original_cursor_pos[1]
    let l:new_line = s:state.original_cursor_pos[1] + l:line_offset + len(l:lines) - 1
    call cursor(l:new_line, len(getline(l:new_line)))
  endif

  " Add footer if not already added and response has started
  if s:state.response_started && !s:state.footer_added
    let s:state.footer_added = 1
    call append('.', '')
    call append('.', '')

    " Random emoticon
    let l:emoticon = s:ui.active_emoticons[s:state.emoticon_index]
    let l:loading_tag = s:ui.loading_tags[s:state.dots_state]

    " Add footer line
    call append('.', l:emoticon . s:ui.footer_base . ' ' . l:loading_tag)

    " Start footer animation timer
    if s:state.thinking_timer == v:null
      let s:state.thinking_timer = timer_start(400, 's:animate_footer', {'repeat': -1})
    endif

    " Move cursor back to content position
    call cursor(l:new_line, len(getline(l:new_line)))
  endif

  redraw
endfunction

" Prepare API request arguments
function! s:make_anthropic_curl_args(prompt) abort
  call s:debug_log("Preparing API request with " . len(s:context.entries) . " context entries")

  " Validate API key
  let l:api_key = s:get_api_key(s:config.effective.api_key_name)
  if empty(l:api_key)
    call s:debug_log("Error: API key not found in environment")
    echoerr "API key not found in environment variable " . s:config.effective.api_key_name
    return []
  endif

  " Prepare content blocks
  let l:content_blocks = []

  " Process context entries first
  for entry in s:context.entries
    try
      let l:content = has_key(s:context.cache, entry.id)
            \ ? s:context.cache[entry.id]
            \ : s:load_file_with_progress(entry.expanded_path, entry.type)

      if entry.type ==# 'text'
        if !empty(l:content)
          let l:block = {'type': 'text', 'text': l:content}
          call add(l:content_blocks, l:block)
        endif
      elseif entry.type ==# 'media'
        let l:block = {
              \ 'type': entry.media_type =~# '^image/' ? 'image' : 'document',
              \ 'source': {
              \   'type': 'base64',
              \   'media_type': entry.media_type,
              \   'data': l:content
              \   }
              \ }

        call add(l:content_blocks, l:block)
      endif
    catch
      let l:error_msg = "Failed to process context " . entry.filepath . ": " . v:exception
      call s:debug_log("Error: " . l:error_msg)
      echoerr l:error_msg
      return []
    endtry
  endfor

  " Add user prompt last
  call add(l:content_blocks, {'type': 'text', 'text': a:prompt, 'cache_control': {'type': 'ephemeral'}})

  " Get the wrap column and build instruction text
  let l:wrap_col = s:get_wrap_column()
  let l:instruction_text = 'Maintain a strict line length of less than ' . (l:wrap_col + 1) . '.'
  let l:repeated_instruction = repeat(l:instruction_text . ' ', 5)

  " Build request data
  let l:data = {
        \ 'messages': [{'role': 'user', 'content': l:content_blocks}],
        \ 'model': s:config.effective.model,
        \ 'stream': v:true,
        \ 'max_tokens': s:config.effective.max_tokens,
        \ 'temperature': s:config.effective.temperature,
        \ 'system': [
        \     {
        \         'type': 'text',
        \         'text': s:config.effective.system_prompt
        \     },
        \     {
        \         'type': 'text',
        \         'text': '<instruction+>' . l:repeated_instruction . '</instruction+>'
        \     }
        \ ]
        \ }

  if s:config.reasoning_level >= 1
    let l:thinking_budget = s:config.reasoning_level == 1 ? 16000 : 32000
    let l:data.thinking = {
          \ 'type': 'enabled',
          \ 'budget_tokens': l:thinking_budget
          \ }
  endif

  if s:debug.enabled
    let l:debug_data = s:sanitize_for_debug(l:data)
    call s:debug_log("Request data structure: " . string(l:debug_data))
  endif

  " Build curl arguments with explicit header handling
  let l:headers = [
        \ 'Content-Type: application/json',
        \ 'x-api-key: ' . l:api_key,
        \ 'anthropic-version: 2023-06-01'
        \ ]

  " Add beta header for extended output if enabled
  if s:config.reasoning_level == 2
    call add(l:headers, 'anthropic-beta: output-128k-2025-02-19')
  endif

  " Build arg list efficiently
  let l:args = ['-N', '-X', 'POST']

  if s:debug.enabled
    call extend(l:args, ['-v', '--stderr'])
    let l:error_log = tempname()
    call add(l:args, l:error_log)
    let s:debug.curl_error_log = l:error_log
  endif

  " Add headers efficiently
  for header in l:headers
    call extend(l:args, ['-H', header])
  endfor

  " Add data and URL
  let l:json_data = json_encode(l:data)
  call extend(l:args, ['-d', l:json_data, s:config.effective.url])

  return l:args
endfunction

" Handle API response data
function! s:handle_anthropic_data(data) abort
  " Append new data to the buffer
  let s:state.event_buffer .= a:data

  " Find complete events (ending with double newline)
  let l:complete_events = []
  let l:start_pos = 0
  let l:end_pos = -1

  " Find positions of all double newlines
  while 1
    let l:end_pos = match(s:state.event_buffer, "\n\n", l:start_pos)
    if l:end_pos == -1
      break
    endif

    " Extract complete event
    call add(l:complete_events, strpart(s:state.event_buffer, l:start_pos, l:end_pos - l:start_pos + 2))
    let l:start_pos = l:end_pos + 2
  endwhile

  " Update buffer to contain only incomplete event data
  if l:start_pos > 0
    let s:state.event_buffer = strpart(s:state.event_buffer, l:start_pos)
  endif

  " Process complete events
  for l:raw_event in l:complete_events
    " Parse event lines
    let l:event_type = ''
    let l:data_content = ''
    let l:lines = split(l:raw_event, "\n")

    for l:line in l:lines
      if l:line =~# '^event: '
        let l:event_type = l:line[7:]
      elseif l:line =~# '^data: '
        let l:data_content = l:line[6:]
      endif
    endfor

    " Skip if we didn't find valid event data
    if empty(l:event_type) || empty(l:data_content)
      continue
    endif

    try
      let l:json = json_decode(l:data_content)

      " Check for error events
      if l:event_type ==# 'error' || (type(l:json) == v:t_dict && has_key(l:json, 'type') && l:json.type ==# 'error')
        call s:handle_api_error(l:json)
        return
      endif

      " Track thinking block start
      if l:event_type ==# 'content_block_start' && has_key(l:json, 'content_block')
        let l:block = l:json.content_block
        if has_key(l:block, 'type') && l:block.type ==# 'thinking'
          let s:state.in_thinking_block = 1
          let s:state.thinking_content = ''
          call s:write_string_at_cursor("<thinking>\n")
        endif
      endif

      " Handle various delta event types
      if l:event_type ==# 'content_block_delta' && has_key(l:json, 'delta')
        let l:delta = l:json.delta
        let l:delta_type = get(l:delta, 'type', '')

        if l:delta_type ==# 'text_delta' && has_key(l:delta, 'text')
          call s:write_string_at_cursor(l:delta.text)
        elseif l:delta_type ==# 'thinking_delta' && has_key(l:delta, 'thinking')
          let s:state.thinking_content .= l:delta.thinking
          call s:write_string_at_cursor(l:delta.thinking)
        endif
      endif

      " Track thinking block end
      if l:event_type ==# 'content_block_stop' && s:state.in_thinking_block
        call s:write_string_at_cursor("\n</thinking>\n\n")
        let s:state.in_thinking_block = 0
      endif
    catch
      call s:debug_log("JSON parse error: " . v:exception)
      continue
    endtry
  endfor
endfunction

" Handle API errors
function! s:handle_api_error(error) abort
  " Extract error information
  if type(a:error) != v:t_dict || !has_key(a:error, 'error')
    call s:debug_log("Invalid error format")
    return
  endif

  let l:error = a:error.error
  let l:type = get(l:error, 'type', 'unknown_error')
  let l:message = get(l:error, 'message', 'Unknown error occurred')

  call s:debug_log("Handling API error: " . l:type)
  call s:debug_log("Error message: " . l:message)

  " Clean up any thinking animation
  call s:stop_thinking_animation()

  " Force redraw to ensure buffer is clean
  redraw!

  echoerr l:type . ": " . l:message

  " Cancel the current job and reset state
  call s:cancel_job()
endfunction

"-----------------------------------------------------------------------------
" Job Management Functions
"-----------------------------------------------------------------------------

" Handle job output
function! s:job_out_callback(channel, msg)
  call s:debug_log("Response chunk received, length: " . len(a:msg))
  call s:handle_anthropic_data(a:msg)
endfunction

" Handle job errors
function! s:job_err_callback(channel, msg)
  call s:debug_log("Error from job: " . a:msg)
endfunction

" Handle job exit
function! s:job_exit_callback(job, status)
  call s:debug_log("Job exited with status: " . a:status)

  " Process curl error log if available
  if !empty(s:debug.curl_error_log) && filereadable(s:debug.curl_error_log)
    let l:errors = readfile(s:debug.curl_error_log)
    if !empty(l:errors)
      call s:debug_log("Curl debug output:")
      for l:line in l:errors
        call s:debug_log("Curl: " . l:line)
      endfor
    endif
    call delete(s:debug.curl_error_log)
    let s:debug.curl_error_log = ''
  endif

  " Clean up temporary data file
  if !empty(s:state.temp_data_file) && filereadable(s:state.temp_data_file)
    call s:debug_log("Cleaning up temp file: " . s:state.temp_data_file)
    call delete(s:state.temp_data_file)
    let s:state.temp_data_file = ''
  endif

  " Remove trailing whitespace from response
  let l:save = winsaveview()
  %s/\s\+$//ge
  call winrestview(l:save)

  " Stop any thinking timer
  if s:state.thinking_timer != v:null
    call timer_stop(s:state.thinking_timer)
    let s:state.thinking_timer = v:null
  endif

  " Update footer with completion status
  if s:state.footer_added
    let l:last_line = line('$')
    let l:rand_index = rand() % len(s:ui.final_emoticons)
    let l:final_emoticon = s:ui.final_emoticons[l:rand_index]
    call setline(l:last_line, l:final_emoticon . s:ui.footer_base . ' ' . s:ui.term_tag)
  endif

  " Move cursor to position 1 of line below response
  call append('.', '')
  normal! j0

  let s:state.active_job = v:null
  if hasmapto('s:cancel_job')
    silent! nunmap <Esc>
  endif
  call s:reset_state()
endfunction

" Cancel the current job
function! s:cancel_job()
  if s:state.active_job != v:null
    call job_stop(s:state.active_job)
    let s:state.active_job = v:null
    if hasmapto('s:cancel_job')
      silent! nunmap <Esc>
    endif

    " Clean up temporary data file if it exists
    if !empty(s:state.temp_data_file) && filereadable(s:state.temp_data_file)
      call s:debug_log("Cleaning up temp file on cancel: " . s:state.temp_data_file)
      call delete(s:state.temp_data_file)
      let s:state.temp_data_file = ''
    endif

    " If footer was added, update it to show cancellation
    if s:state.footer_added
      let l:last_line = line('$')
      let l:rand_index = rand() % len(s:ui.final_emoticons)
      let l:final_emoticon = s:ui.final_emoticons[l:rand_index]
      call setline(l:last_line, l:final_emoticon . s:ui.footer_base . ' <CLAUDIA ABRT>')
    endif

    " Stop thinking animation
    call s:stop_thinking_animation()
    call s:reset_state()
  endif
endfunction

"-----------------------------------------------------------------------------
" Main Plugin Functions
"-----------------------------------------------------------------------------

" Trigger claudia from normal mode
function! s:trigger_claudia() abort
  call s:reset_state()
  let s:state.original_cursor_pos = getpos('.')

  " Get prompt from visual selection or cursor position
  if s:state.from_visual_mode
    let l:prompt = s:get_visual_selection()
    let l:end_line = line("'>")
    execute "normal! \<Esc>"
    call append(l:end_line, '')
    execute "normal! " . (l:end_line + 1) . "G"
    let s:state.from_visual_mode = 0
  else
    let l:prompt = s:get_lines_until_cursor()
    call append('.', '')
    normal! j
  endif

  call s:start_thinking_animation()

  " Get curl arguments
  let l:args = s:make_anthropic_curl_args(l:prompt)
  if empty(l:args)
    call s:stop_thinking_animation()
    return
  endif

  " Create a temporary file for the JSON data
  let l:temp_file = tempname()
  call s:debug_log("Created temp file: " . l:temp_file)

  " Extract JSON data efficiently
  let l:json_data = ''
  let l:filtered_args = []
  let i = 0
  while i < len(l:args)
    if l:args[i] ==# '-d' && i < len(l:args) - 1
      let l:json_data = l:args[i + 1]
      let i += 2  " Skip both -d and its value
    else
      call add(l:filtered_args, l:args[i])
      let i += 1
    endif
  endwhile

  " Write JSON data to temp file
  call writefile([l:json_data], l:temp_file)
  let s:state.temp_data_file = l:temp_file

  " Build curl command efficiently
  let l:curl_cmd = 'curl -N -s --no-buffer'
  let l:arg_string = join(map(l:filtered_args, 'shellescape(v:val)'), ' ')
  let l:curl_cmd .= ' ' . l:arg_string . ' -d @' . shellescape(l:temp_file)

  call s:debug_log("Using curl command: " . l:curl_cmd)

  " Execute curl in background
  let s:state.active_job = job_start(['/bin/sh', '-c', l:curl_cmd], {
        \ 'out_cb': 's:job_out_callback',
        \ 'err_cb': 's:job_err_callback',
        \ 'exit_cb': 's:job_exit_callback',
        \ 'mode': 'raw'
        \ })

  " Allow cancellation with Escape
  nnoremap <silent> <Esc> :call <SID>cancel_job()<CR>
endfunction

" Trigger claudia from visual mode
function! s:trigger_visual() abort
  let s:state.from_visual_mode = 1
  call s:trigger_claudia()
endfunction

"-----------------------------------------------------------------------------
" Command Definitions
"-----------------------------------------------------------------------------

" Commands for runtime configuration
command! ClaudiaShowConfig call s:show_config()
command! -nargs=1 -complete=file ClaudiaSystemPrompt call s:set_system_prompt(<q-args>)
command! -nargs=1 ClaudiaTemp call s:set_temperature(<q-args>)
command! -nargs=1 ClaudiaTokens call s:set_max_tokens(<q-args>)
command! ClaudiaResetConfig call s:init_config()

" Reasoning mode commands
command! -nargs=1 ClaudiaReason call s:set_reasoning_mode(<args>)

" Context management commands
command! -nargs=1 -complete=file ClaudiaAddContext call s:add_context(<q-args>)
command! -nargs=1 ClaudiaRemoveContext call s:remove_context(<q-args>)
command! ClaudiaShowContext call s:show_context()
command! ClaudiaClearContext call s:clear_context()

" Cache management commands
command! -nargs=1 ClaudiaCacheContext call s:cache_context(<q-args>)
command! -nargs=1 ClaudiaUncacheContext call s:uncache_context(<q-args>)
command! ClaudiaClearCache call s:clear_cache()

" Debug commands
command! ClaudiaToggleDebug call s:toggle_debug()
command! ClaudiaShowDebugLog call s:show_debug_log()

"-----------------------------------------------------------------------------
" Plugin Mappings
"-----------------------------------------------------------------------------

" Define plugin mappings
nnoremap <silent> <script> <Plug>ClaudiaTrigger :call <SID>trigger_claudia()<CR>
if !hasmapto('<Plug>ClaudiaTrigger') && empty(maparg('<Leader>c', 'n'))
  nmap <silent> <Leader>c <Plug>ClaudiaTrigger
endif

xnoremap <silent> <script> <Plug>ClaudiaTriggerVisual :<C-u>call <SID>trigger_visual()<CR>
if !hasmapto('<Plug>ClaudiaTriggerVisual') && empty(maparg('<Leader>c', 'x'))
  xmap <silent> <Leader>c <Plug>ClaudiaTriggerVisual
endif

" Initialize the plugin
call s:init_config()

" Restore cpo
let &cpo = s:save_cpo
unlet s:save_cpo
