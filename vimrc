" $HOME/.vimrc
" ┌─────────────┐
" │╻ ╻╻┏┳┓┏━┓┏━╸│
" │┃┏┛┃┃┃┃┣┳┛┃  │
" │┗┛ ╹╹ ╹╹┗╸┗━╸│
" └─────────────┘

set encoding=utf-8 fileencodings=
execute pathogen#infect()
syntax on
set nocompatible
let g:airline#extensions#tabline#enabled = 1

" let g:UltiSnipsUsePythonVersion = 3
" let g:UltiSnipsExpandTrigger="<tab>"
" let g:UltiSnipsJumpForwardTrigger="<c-b>"
" let g:UltiSnipsJumpBackwardTrigger="<c-z>"
" let g:UltiSnipsSnippetsDir="$HOME/.vim/"
" let g:UltiSnipsEditSplit="vertical"

map ; :

filetype plugin on
let mapleader=","
set timeout timeoutlen=1500
filetype plugin indent on

syntax on

set expandtab                  " Tab -> spaces
set nowrap                     " don't wrap lines
set textwidth=79
set tabstop=4                  " a tab is four spaces
set backspace=indent,eol,start " allow backspacing over everything in insert mode
set autoindent                 " always set autoindenting on
set copyindent                 " copy the previous indentation on autoindenting
set number                     " always show line numbers
set shiftwidth=4               " number of spaces to use for autoindenting
set shiftround                 " use multiple of shiftwidth when indenting with '<' and '>'
set showmatch                  " set show matching parenthesis
set ignorecase                 " ignore case when searching
set smartcase                  " ignore case if search pattern is all lowercase,  case-sensitive otherwise
set smarttab                   " insert tabs on the start of a line according to shiftwidth, not tabstop
set hlsearch                   " highlight search terms
set incsearch                  " show search matches as you type
set history=1000               " remember more commands and search history
set undolevels=1000            " use many muchos levels of undo
set wildignore=*.swp,*.bak,*.pyc,*.class
set title                      " change the terminal's title
set visualbell                 " don't beep
set noerrorbells               " don't beep

set pastetoggle=<F2>

" for when we forget to use sudo to open/edit a file
cmap w!! w !sudo tee % >/dev/null

" ctrl-jklm  changes to that split
map <c-j> <c-w>j
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

""" Tabulation completion
" Try different completion methods depending on its context
let g:SuperTabDefaultCompletionType = "context"
set wildmenu                   " Menu completion in command mode on <Tab>
set wildmode=full              " <Tab> cycles between all matching choices.

" Search down into subfolders
" Provides tab-completion for all file-related tasks
set path+=**

""" Insert completion
" don't select first item, follow typing in autocomplete
set completeopt=menuone,longest,preview
set pumheight=6                " Keep a small completion window

" show a line at column 79
if exists("&colorcolumn")
    set colorcolumn=79
endif

""" Moving Around/Editing
set cursorline                 " have a line indicate the cursor location
set ruler                      " show the cursor position all the time
set nostartofline              " Avoid moving cursor to BOL when jumping around

"""" Reading/Writing
set noautowrite                " Never write a file unless I request it.
set noautowriteall             " NEVER.
set noautoread                 " Don't automatically re-read changed files.
set modeline                   " Allow vim options to be embedded in files;
set modelines=5                " they must be within the first or last 5 lines.
set ffs=unix,dos,mac           " Try recognizing dos, unix, and mac line endings.

"""" Messages, Info, Status
set ls=2                       " allways show status line
set vb t_vb=                   " Disable all bells.  I hate ringing/flashing.
set confirm                    " Y-N-C prompt if closing with unsaved changes.
set showcmd                    " Show incomplete normal mode commands as I type.
set report=0                   " : commands always print changed line count.
set shortmess+=a               " Use [+]/[RO]/[w] for modified/readonly/written.
set ruler                      " Show some info, even without statuslines.
set laststatus=2               " Always show statusline, even if only 1 window.
set statusline=%<%f\ (%{&ft})%=%-19(%3l,%02c%03V%)

""" Searching and Patterns
set ignorecase                 " Default to using case insensitive searches,
set smartcase                  " unless uppercase letters are used in the regex.
set hlsearch                   " Highlight searches by default.
set incsearch                  " Incrementally search while typing a /regex


" Load up virtualenv's vimrc if it exists
if filereadable($VIRTUAL_ENV . '/.vimrc')
    source $VIRTUAL_ENV/.vimrc
endif

"""" Display
colorscheme molokai
let g:molokai_original = 1
let g:rehash256 = 1
set laststatus=2

"""" Display trailings chars
highlight ExtraWhitespace ctermbg=darkgreen guibg=darkgreen
match ExtraWhitespace /\s\+$/

" set 5 lines to the cursor when moving aroung
set so=5

" enable undo even when the fileis closed
set undodir=$HOME/.vim/undodir
set undofile

set list listchars=tab:»·,trail:·
