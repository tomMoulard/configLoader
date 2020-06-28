" $HOME/.vimrc
" ┌─────────────┐
" │╻ ╻╻┏┳┓┏━┓┏━╸│
" │┃┏┛┃┃┃┃┣┳┛┃  │
" │┗┛ ╹╹ ╹╹┗╸┗━╸│
" └─────────────┘
" Maintainer:
"  tom at moulard dot org
" Complete_version:
"  You can file the updated version on the git repository
"  github.com/tommoulard/configloader

set nocompatible               " Enter the new millennium

" main mappings
map ; :                        " Map semicolon to colon
let mapleader=" "              " Set <leader> to space
let g:mapleader=" "

" Tabulation completion
set wildmenu                   " Menu completion in command mode on <Tab>
set wildmode=full              " <Tab> cycles between all matching choices.
set path+=**                   " Search down into sub folders
set completeopt=menuone,longest,preview " Don't select first item, follow typing in auto complete
set pumheight=6                " Keep a small completion window

" Moving Around
set nostartofline              " Avoid moving cursor to BOL when jumping around

" Reading/Writing
set encoding=utf-8             " Vim encoding
set fileencodings=utf-8        " File encoding
set noautowrite                " Never write a file unless I request it.
set noautowriteall             " NEVER.
set noautoread                 " Don't automatically reread changed files.
set modeline                   " Allow vim options to be embedded in files;
set modelines=5                " they must be within the first or last 5 lines.
set fileformats=unix,dos,mac   " Try recognizing dos, Unix, and mac line endings.
set secure                     " do not allow to write commands, :autocmd and shell in ~/.vimrc
set pastetoggle=<F2>           " Toggle PASTE mode
set nowrap                     " Don't wrap lines
set backspace=indent,eol,start " Allow backspacing over everything in insert mode
filetype plugin on             " Allow file type detection

" Messages, Info
set confirm                    " Y-N-C prompt if closing with unsaved changes.
set showcmd                    " Show incomplete normal mode commands as I type.
set report=0                   " : commands always print changed line count.
set shortmess+=a               " Use [+]/[RO]/[w] for modified/read only/written.

" Indentation
set expandtab                  " Tab -> spaces
set tabstop=4                  " a tab is four spaces
set autoindent                 " always set auto indenting on
set copyindent                 " copy the previous indentation on auto indenting
set shiftwidth=4               " number of spaces to use for auto indenting
set shiftround                 " use multiple of shift width when indenting with '<' and '>'
set smarttab                   " insert tabs on the start of a line according to shift width, not tab stop
set cinoptions=(0,u0,U0,t0,g0  " fixing indent, see :help cinoptions-values
filetype indent on             " Allow indent customization from file type

" Searching and Patterns
set hlsearch                   " highlight search terms
set ignorecase                 " ignore case when searching
set incsearch                  " Incrementally search while typing a /regex
set magic                      " For regular expressions turn magic on
set showmatch                  " show matching parenthesis
set smartcase                  " ignore case if search pattern is all lowercase,  case sensitive otherwise
set wildignore=*.swp,*.bak,*.pyc,*.class,*.o

" Sounds
set noerrorbells               " Don't beep
set visualbell t_vb=           " Disable all bells.  I hate ringing/flashing.

" Load up virtualenv's vimrc if it exists
if filereadable($VIRTUAL_ENV . '/.vimrc')
    source $VIRTUAL_ENV/.vimrc
endif

" Display
colorscheme molokai
let g:molokai_original = 1
let g:rehash256 = 1

" Customize gui
syntax enable                  " Enable syntax processing
set lazyredraw                 " Lazy redraw during macros
set sidescroll=5               " To make scrolling horizontally a bit more useful
set number                     " Always show line numbers
set relativenumber             " Show relative line numbers, useful for functions
set title                      " Change the terminal's title
set laststatus=2               " Always show status line, even if only 1 window.
set statusline=%<%f\ (%{&ft})%=%-19(%3l,%02c%03V%)
set noshowmode                 " Disable default status line
set list                       " Show chars on VISUAL mode
set listchars=tab:»·,trail:·,eol:\ ,extends:>,precedes:<,nbsp:¤
set ruler                      " Show the cursor position all the time
set rulerformat=%15(%c%V\ %p%%%) " Display a better ruler
set nocursorcolumn             " Remove a line indicating the cursor column
set cursorline                 " Have a line indicate the cursor location
set matchpairs+=\":\"          " match quotes when typing
set matchpairs+=':'            " match single quote when typing
set scrolloff=5                " Set 5 lines to the cursor when moving around

" Status line function
function! StatuslineGit()
    let l:branchname = system("git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\n'")
    return strlen(l:branchname) > 0?'['.l:branchname.']':''
endfunction

" Status line
set titlelen=85                " Fix the max length of title, therefore align text with the available space
set titlestring=%<             " Change the terminal title with fancy text
set titlestring+=%r            " Readonly flag, text is "[RO]".
set titlestring+=%m            " Modified flag, text is "[+]"; "[-]" if 'modifiable' is off.
set titlestring+=%{StatuslineGit()} " Display current git branch
set titlestring+=%F            " Full path to the file in the buffer.
set titlestring+=\ -\ %{&fileencoding?&fileencoding:&encoding}
set titlestring+=%=            " Separation point between left and right aligned items.
set titlestring+=%b            " Value of character under cursor.
set titlestring+=-%B           " As above, in hexadecimal.
set titlestring+=\ %c          " Column number.
set titlestring+=,%l           " Line number.
set titlestring+=/%L           " Number of lines in buffer.
set titlestring+=(%p%%)          " Percentage through file in lines as in CTRL-G.

" Show a line at column 79
if exists("&colorcolumn")
    set colorcolumn=79         " Display a line at 79 char
endif

" Change cursor color on urxvt
if &term =~ "xterm\\|rxvt"
    " use an red cursor in REPLACE mode
    let &t_SR = "\<Esc>]12;red\x7"
    " use a white cursor otherwise
    let &t_EI = "\<Esc>]12;white\x7"
    silent !echo -ne "\033]12;white\007"
    " reset cursor when vim exits
    autocmd VimLeave * silent !echo -ne "\033]112\007"
endif

" Display trailing chars
highlight ExtraWhitespace ctermbg=darkgreen guibg=darkgreen
match ExtraWhitespace /\s\+$/

" Undo
set undodir=$HOME/.vim/undodir " Set folder to store undo files
set undofile                   " Allow persistent undo
set undolevels=1000            " Use many levels of undo
set history=1000               " Remember more commands and search history

" Timeout
set timeout                    " Set a timeout to commands
set timeoutlen=1500            " Set timeout value to commands

" Save
nnoremap <Leader>w :update<CR> " <space>w writes a files only if modified
nnoremap <Leader><Leader> :update<CR>
" For when we forget to use sudo to open/edit a file
cmap w!! w !sudo tee % >/dev/null

" Use <Leader>W to strip all trailing white spaces in the current file
nnoremap <Leader>W :%s/\s\+$//<CR>:let @/=''<CR>

" Splitting window
nnoremap <F11> :split<CR>      " Do a horizontal split with <F11>
nnoremap <F12> :vsplit<CR>     " Do a vertical split with <F12>

" Ctrl-jklm  changes to that split
map <c-j> <c-w>j               " move cursor to down split
map <c-k> <c-w>k               " move cursor to up split
map <c-l> <c-w>l               " move cursor to right split
map <c-h> <c-w>h               " move cursor to left split

" windows like
nnoremap <C-c> "+y
nnoremap <C-v> "+p
nnoremap <C-s> :update<CR>

" Auto make
nnoremap <F5> :make<CR><c-w> "auto make

" Add ad matching char
imap ( ()<C-[>i
imap [ []<C-[>i
imap { {}<C-[>i
imap < <><C-[>i

" Autocmd to have custom settings depending on file type
autocmd FileType c,cpp,java setlocal matchpairs+==:; " jump between the '=' and ';'
autocmd FileType html setlocal matchpairs+=<:>       " adding a pair of <>
autocmd FileType c setlocal makeprg=cc\ %\ $*
autocmd FileType html setlocal makeprg=$BROWSER\ %\ $*
autocmd FileType markdown setlocal makeprg=pandoc\ %\ $*\ \-o\ %.pdf

" Proper comments (<leader>cc to comment, <leader>cu to uncomment, <Leader>c<space> to toggle)
autocmd FileType python,sh setlocal commentstring=#\ %s
autocmd FileType html setlocal commentstring=<!--\ %s\ -->
autocmd FileType xdefaults setlocal commentstring=!\ %s
autocmd FileType vim setlocal commentstring=\"\ %s

" Turn off search highlighting
nmap <leader>, :nohlsearch<CR>

" Spell check
" z=    " change word
" ]s    " jump to next misspelled word
" zg    " add a word to dictionary
" zw    " mark a word misspelled
map <F6> :setlocal spell! spelllang=fr,en_us<CR>

" Set dictionary (Its used with C-X C-K to auto complete words)
set dictionary=/usr/share/dict/words

" Plugins
execute pathogen#infect()
" Airline
let g:airline#extensions#tabline#enabled = 1

" Adding markdown syntax highlighter
let g:markdown_fenced_languages = ['html', 'python', 'bash=sh']
let g:markdown_syntax_conceal = 0
let g:markdown_minlines = 100

" Nerdtree
nnoremap <F1> :NERDTreeToggle<CR>
autocmd StdinReadPre * let s:std_in=1
" Open Nerdtree when no file is provided to vim
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" Nerdcommenter
let g:NERDSpaceDelims = 1
let g:NERDTreeShowHidden=1
let g:NERDCompactSexyComs = 1
let g:NERDTrimTrailingWhitespace = 1

" Multicursor
let g:multi_cursor_quit_key = '<Esc>'

" CtrlP
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden -g ""'

" supertab
" This allow to scoll auto complete top to bottom
let g:SuperTabDefaultCompletionType = "<c-n>"

" ultisnips
" Create snippets using :UltiSnipsEdit
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"
" let g:UltiSnipsEditSplit="vertical"
let g:UltiSnipsSnippetsDir = "~/.vim/UltiSnips/"

