# My Vim configuration

## Comments
This is a list of vim commands sorted alphabetically (`:12kt<CR\>V't:sort<CR\>`)

`<leader>` is set to <space\>

This is a non exhaustive list not all sub commands are shown (i.e. V'<mark\>), you might want to look at `:help` and `:map`

|Command|Description|
|-------|-----------|
|"<char\>p|Paste from <char\> buffer|
|"<char\>y|Yank to <char\> buffer|
|$|Move cursor at the end of line|
|%|Match next item ((,[,{,<,") and jump to it|
|'<char\>|Jump to <char\> mark|
|(|Move cursor at the beginning of the sentence|
|)|Move cursor at the end of the sentence|
|.|Redo command|
|/<word\>|Search for <word\>|
|0|Move cursor at the beginning of the line|
|:!<command\>|Run <command\> in shell|
|:%s/<1\>/<2\>/g|Replace <1\> with <2\> (g for more than once per line)|
|:<[0-9]+\>|Move cursor to line|
|:G<command\>|Do git <command\> inside Vim (i.e. `:Gdiff`)|
|:UltiSnipsEdit|Edit snippets for current file type|
|:bd|Close current buffer|
|:bn|Go to next buffer|
|:bp|Go to previous buffer|
|:cd <dir\>|move vim root dir to <dir\>|
|:cn|Goto next error, next quickfix|
|:copen|Open a windows with a list of errors|
|:cp|Goto previous error|
|:dig|Shows special char for <ctrl-k>|
|:e <file\>|Open file|
|:h <command\>|Show help for this command|
|:help <command\>|Show help for this command|
|:ls|List current buffers|
|:make|Build file / project|
|:marks|Show marks|
|:nohlsearch|Turn off search highlighting|
|:nohl|Turn off search highlighting|
|:q!|Quit without save (forced)|
|:q|Quit without save|
|:r <file\>|Insert content of <file\>|
|:r!<command\>|Insert the result of the shell <command\>|
|:update|Save file only if there is changes|
|:w <file name\>|Save as <file name\>|
|:w!!|Save a file even when open without sudo (still need sudo pwd)|
|:wq|Save and exit|
|:w|Save file|
|:x|Save and close file|
|<F10\>|DAP: step over|
|<F11\>|DAP: step into|
|<F11\>|Do a horizontal split|
|<F12\>|DAP: step out|
|<F12\>|Do a vertical split|
|<F1\>|Toggle NerdTree|
|<F2\>|Toggle PASTE mode|
|<F3\>|Open a terminal|
|<F5\>|Make file or start DAP|
|<F6\>|Toggle spelling|
|<F9\>|Toggle DAP UI|
|<Tab\>|Auto complete + snippets|
|<[0-9]+\>@<char\>|Applies a number of time a macro (<char\>)|
|<[0-9]+\>G|Move cursor to line|
|<c-b\>|Go up half a page|
|<c-e\>|Move screen up|
|<c-f\>|Go down half a page|
|<c-g\>|Display information about the file|
|<c-h\>|Move cursor to left split|
|<c-i\>|Jump to next place|
|<c-j\>|Move cursor to bottom split|
|<c-k\>XX(in insert mode)|Insert special char, see :dig|
|<c-k\>|Move cursor to top split|
|<c-l\>|Move cursor to right split|
|<c-o\>|Jump to previous place|
|<c-p\>|Open file using CtrlP|
|<c-r\><register\>|In INSERT mode, paste the content of the <register\> (a macro, ...)|
|<c-r\>|Redo|
|<c-w\>=|Resize all split to default value|
|<c-w\>H|change split to vertical|
|<c-w\>K|change split to horizontal|
|<c-w\>\_|Full screen current horizontal split|
|<c-w\>\||Full screen current vertical split|
|<c-w\>w|Move to next split|
|<c-x\><c-f\>|When on INSERT mode, autocomplete file names|
|<c-x\><c-l\>|When on INSERT mode, autocomplete whole sentences|
|<c-x\><c-o\>|When on INSERT mode, autocomplete depending on the file type|
|<c-y\>|Move screen down|
|<c-z\>|Halt vim to cli, revert with fg|
|<leader\>,|Turn off search highlighting|
|<leader\><leader\>|Save file|
|<leader\>B|DAP: set breakpoint|
|<leader\>W|Remove trailing white space|
|<leader\>b|DAP: toggle breakpoint|
|<leader\>c<space\>|Toggle selected area comment|
|<leader\>cc|Comment selected area|
|<leader\>cu|Uncomment selected area|
|<leader\>df|DAP: Opens frames in a centered floating window|
|<leader\>df|DAP: Opens scopes in a centered floating window|
|<leader\>dh|DAP: View the value for the expression under the cursor in a floating window|
|<leader\>dl|DAP: run last|
|<leader\>dp|DAP: Like <leader\>dh but uses the preview window|
|<leader\>dr|DAP: open REPL|
|<leader\>lp|DAP: set log message|
|<|Indent down line (or selected area)|
|==|Indent the line|
|=|In VISUAL mode, indent the selected area|
|A|INSERT mode at the end of line|
|C|Delete the end of line and go into INSERT mode|
|G=gg|Indent the whole file|
|G|Go to the end of the file|
|H|Move cursor at the top of the screen|
|I|INSERT mode at the beginning of a line|
|J|Join lines (removes indent and \\n, add a <space\>)|
|K|Show vim help about the word under the cursor|
|L|Move cursor at the bottom of the screen|
|M|Move cursor at the middle of the screen|
|N|Go to previous highlighted value|
|O|INSERT mode to the line on top the cursor|
|P|Paste up|
|R|REPLACE mode until <Esc\>|
|V|VISUAL mode with whole lines|
|ZZ|Save and exit|
|[M|go to end of previous function|
|[m|go to previous function|
|[s|go to previous misspelled word|
|\*|Highlight word under cursor and jump to next occurrence|
|\>|Indent line (or selected area)|
|]M|go to end of next function|
|]m|go to next function|
|]s|go to next misspelled word|
|^|Move cursor at the beginning of a line|
|a|INSERT mode after cursor|
|b|Move cursor backward on word|
|cc|Delete a line and go into INSERT mode|
|dd|Delete line|
|dt<char\>|Remove characters until next <char\>|
|echo &<command\>|Display <command\> value|
|e|Move cursor at the end of next word|
|g??|Do rot13 on selected text|
|gcc|go coverage toggle|
|gdt|go debug test|
|ge|Move cursor at the end of previous word|
|gf|open file from path under the cursor|
|gg|Go to the beginning of the file|
|gtf|go test func|
|gtt|go test|
|gww|Format current line using wrap|
|gw|Format selected text using wrap|
|h|Move cursor left|
|i|INSERT mode at cursor|
|j|Move cursor down|
|k|Move cursor up|
|l|Move cursor right|
|m'|Jump to next mark|
|m<char\>|Remove <char\> marker (if <char\> marker is set)|
|m<char\>|Set <char\> marker|
|n|Go to next highlighted value|
|o|INSERT mode to the line under the cursor|
|p|Paste down|
|q<char\>|Record a macro, store it in <char\> stop with q|
|r|replace a char at a time|
|u|Undo|
|v|VISUAL mode|
|w|Move cursor to next word|
|x|Remove a <char\> at a time|
|yy|Yank|
|z-|Move line at the bottom of the screen|
|z.|Move line at the center of the screen|
|z=|fix misspelled word|
|zM|Close all fold|
|zR|Open all fold|
|za|Toggle fold open and closed|
|zb|Move line at the bottom of the screen|
|zc|Close fold|
|zf<command\>|Create fold using <command\> (like zf3j or V'tzf)|
|zg|add work to dict|
|zo|Open fold|
|zt|Move line at the top of the screen|
|zw|Mark a work as misspelled|
|zz|Center screen to cursor|
|{|Move cursor on top of the paragraph|
|}|Move cursor at the end of paragraph|
|£|Highlight word under cursor and jump to previous occurrence|
