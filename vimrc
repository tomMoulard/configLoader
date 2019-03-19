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

map ; :

filetype plugin on
let mapleader=" "
let g:mapleader=" "
set timeout timeoutlen=1500
filetype plugin indent on

set expandtab                  " Tab -> spaces
set nowrap                     " don't wrap lines
set textwidth=79
set tabstop=4                  " a tab is four spaces
set backspace=indent,eol,start " allow backspacing over everything in insert mode
set autoindent                 " always set auto indenting on
set copyindent                 " copy the previous indentation on auto indenting
set number                     " always show line numbers
set shiftwidth=4               " number of spaces to use for auto indenting
set shiftround                 " use multiple of shift width when indenting with '<' and '>'
set showmatch                  " set show matching parenthesis
set ignorecase                 " ignore case when searching
set smartcase                  " ignore case if search pattern is all lowercase,  case-sensitive otherwise
set smarttab                   " insert tabs on the start of a line according to shift width, not tab stop
set hlsearch                   " highlight search terms
set incsearch                  " show search matches as you type
set history=1000               " remember more commands and search history
set undolevels=1000            " use many levels of undo
set wildignore=*.swp,*.bak,*.pyc,*.class
set title                      " change the terminal's title
set visualbell                 " don't beep
set noerrorbells               " don't beep

set pastetoggle=<F2>

" For when we forget to use sudo to open/edit a file
cmap w!! w !sudo tee % >/dev/null

" Ctrl-jklm  changes to that split
map <c-j> <c-w>j
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

" Tabulation completion
" Try different completion methods depending on its context
let g:SuperTabDefaultCompletionType = "context"
let g:SuperTabCompletionContexts = ['s:ContextText', 's:ContextDiscover']
set wildmenu                   " Menu completion in command mode on <Tab>
set wildmode=full              " <Tab> cycles between all matching choices.

" Search down into sub folders
" Provides tab-completion for all file-related tasks
set path+=**

" Insert completion
" Don't select first item, follow typing in auto complete
set completeopt=menuone,longest,preview
set pumheight=6                " Keep a small completion window

" Show a line at column 79
if exists("&colorcolumn")
    set colorcolumn=79
endif

" Moving Around/Editing
set cursorline                 " have a line indicate the cursor location
set ruler                      " show the cursor position all the time
set nostartofline              " Avoid moving cursor to BOL when jumping around

" Reading/Writing
set noautowrite                " Never write a file unless I request it.
set noautowriteall             " NEVER.
set noautoread                 " Don't automatically re-read changed files.
set modeline                   " Allow vim options to be embedded in files;
set modelines=5                " they must be within the first or last 5 lines.
set ffs=unix,dos,mac           " Try recognizing dos, Unix, and mac line endings.

" Messages, Info, Status
set ls=2                       " always show status line
set vb t_vb=                   " Disable all bells.  I hate ringing/flashing.
set confirm                    " Y-N-C prompt if closing with unsaved changes.
set showcmd                    " Show incomplete normal mode commands as I type.
set report=0                   " : commands always print changed line count.
set shortmess+=a               " Use [+]/[RO]/[w] for modified/read only/written.
set ruler                      " Show some info, even without status lines.
set laststatus=2               " Always show status line, even if only 1 window.
set statusline=%<%f\ (%{&ft})%=%-19(%3l,%02c%03V%)

" Searching and Patterns
set ignorecase                 " Default to using case insensitive searches,
set smartcase                  " unless uppercase letters are used in the regex.
set hlsearch                   " Highlight searches by default.
set incsearch                  " Incrementally search while typing a /regex
set magic                      " For regular expressions turn magic on

" Load up virtualenv's vimrc if it exists
if filereadable($VIRTUAL_ENV . '/.vimrc')
    source $VIRTUAL_ENV/.vimrc
endif

" Display
colorscheme molokai
let g:molokai_original = 1
let g:rehash256 = 1
set laststatus=2

" Display trailing chars
highlight ExtraWhitespace ctermbg=darkgreen guibg=darkgreen
match ExtraWhitespace /\s\+$/

" Set 5 lines to the cursor when moving around
set scrolloff=5

" Enable undo even when the file is closed
set undodir=$HOME/.vim/undodir
set undofile

set list
set listchars=tab:»·,trail:·,eol:\ ,extends:>,precedes:<,nbsp:¤

" Disable default status line
set noshowmode

" Quick save
nnoremap <Leader>w :update<CR>
nnoremap <Leader><Leader> :update<CR>

" Use <Leader>W to “strip all trailing whitespace in the current file”
nnoremap <Leader>W :%s/\s\+$//<CR>:let @/=''<CR>

" Splitting window
nnoremap <F11> :split<CR>
nnoremap <F12> :vsplit<CR>

" Turn off search highlighting
nmap <leader>, :nohl<CR>

" Spell check
map <F6> :setlocal spell! spelllang=fr<CR>
map <F3> :set spelllang=en_us<CR>

" Plugins
" Airline
let g:airline#extensions#tabline#enabled = 1

" Adding markdown syntax highlighter
let g:markdown_fenced_languages = ['html', 'python', 'bash=sh']
let g:markdown_syntax_conceal = 0
let g:markdown_minlines = 100

" Nerdtree
nnoremap <F1> :NERDTreeToggle<CR>
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" Ultisnip
" let g:UltiSnipsExpandTrigger="<F3>"

" Nerdcommenter
let g:NERDSpaceDelims = 1
let g:NERDCompactSexyComs = 1
let g:NERDTrimTrailingWhitespace = 1

