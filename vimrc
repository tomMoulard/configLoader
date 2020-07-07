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

" Settings {{{1
" main mapping {{{2
" Map semicolon to colon
nnoremap  ; :
let mapleader=" "              " Set <leader> to space
let g:mapleader=" "
" }}}

" Tabulation completion {{{2
set wildmenu                   " Menu completion in command mode on <Tab>
set wildmode=full              " <Tab> cycles between all matching choices.
set path+=**                   " Search down into sub folders
set completeopt=menuone,longest,preview " Don't select first item, follow typing in auto complete
set pumheight=6                " Keep a small completion window
set complete+=k./*             " Enable auto complete with words of the current directory, it might take time
set complete+=kspell           " Auto complete with words of the dictionary
set complete+=k/usr/share/dict/words " Auto complete with more dictionary
set infercase                  " Match current format when tab complete
" }}}

" Moving Around {{{2
set nostartofline              " Avoid moving cursor to BOL when jumping around
" }}}

" Reading/Writing {{{2
set encoding=utf-8             " Vim encoding
set fileencodings=utf-8        " File encoding
set noautowrite                " Never write a file unless I request it.
set noautowriteall             " NEVER.
set noautoread                 " Don't automatically reread changed files.
set modeline                   " Allow vim options to be embedded in files;
set modelines=5                " They must be within the first or last 5 lines.
set fileformats=unix,dos,mac   " Try recognizing dos, Unix, and mac line endings.
set secure                     " Do not allow to write commands, :autocmd and shell in ~/.vimrc
set pastetoggle=<F2>           " Toggle PASTE mode
set nowrap                     " Don't wrap lines
set textwidth=0                " Do not wrap lines !
set backspace=indent,eol,start " Allow backspacing over everything in insert mode
filetype plugin on             " Allow file type detection
set spelllang=fr,en_us         " Spec spell check languages
" }}}

" Messages, Info {{{2
set confirm                    " Y-N-C prompt if closing with unsaved changes.
set showcmd                    " Show incomplete normal mode commands as I type.
set report=0                   " : commands always print changed line count.
set shortmess+=a               " Use [+]/[RO]/[w] for modified/read only/written.
" }}}

" Indentation {{{2
set expandtab                  " Tab -> spaces
set tabstop=4                  " A tab is four spaces
set autoindent                 " Always set auto indenting on
set copyindent                 " Copy the previous indentation on auto indenting
set shiftwidth=4               " Number of spaces to use for auto indenting
set shiftround                 " Use multiple of shift width when indenting with '<' and '>'
set smarttab                   " Insert tabs on the start of a line according to shift width, not tab stop
set cinoptions=(0,u0,U0,t0,g0  " Fixing indent, see :help cinoptions-values
filetype indent on             " Allow indent customization from file type
" }}}

" Searching and Patterns {{{2
if executable('ag')            " Set grep program to ag if available
    setglobal grepprg=ag\ -s\ --vimgrep
endif
set hlsearch                   " Highlight search terms
set ignorecase                 " Ignore case when searching
set incsearch                  " Incrementally search while typing a /regex
set magic                      " For regular expressions turn magic on
set showmatch                  " Show matching parenthesis
set smartcase                  " Ignore case if search pattern is all lowercase,  case sensitive otherwise
set wildignore+=.hg,.git,.svn  " Version control
set wildignore+=*.aux,*.out,*.toc                " LaTeX intermediate files
set wildignore+=*.jpg,*.bmp,*.gif,*.png,*.jpeg   " binary images
set wildignore+=*.o,*.obj,*.exe,*.dll,*.manifest " compiled object files
set wildignore+=*.spl          " compiled spelling word lists
set wildignore+=*.sw?          " Vim swap files
set wildignore+=*.DS_Store     " OSX bullshit
set wildignore+=*.luac         " Lua byte code
set wildignore+=migrations     " Django migrations
set wildignore+=go/pkg         " Go static files
set wildignore+=go/bin         " Go bin files
set wildignore+=go/bin-vagrant " Go bin-vagrant files
set wildignore+=*.pyc          " Python byte code
set wildignore+=*.orig         " Merge resolution files
" }}}

" Sounds {{{2
set noerrorbells               " Don't beep
set visualbell t_vb=           " Disable all bells.  I hate ringing/flashing.
" }}}

" Load up virtualenv's vimrc if it exists {{{2
if filereadable($VIRTUAL_ENV . '/.vimrc')
    source $VIRTUAL_ENV/.vimrc
endif
" }}}

" Display {{{2
colorscheme molokai
let g:molokai_original = 1
let g:rehash256 = 1
" }}}

" Customize gui {{{2
syntax enable                  " Enable syntax processing
set lazyredraw                 " Lazy redraw during macros
set sidescroll=5               " To make scrolling horizontally a bit more useful
set scrolloff=5                " Set 5 lines to the cursor when moving around
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
highlight Normal ctermbg=NONE  " Transparent background color
" }}}

" Status line {{{2
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
set titlestring+=(%p%%)        " Percentage through file in lines as in CTRL-G.

" Status line function
function! StatuslineGit()
    let l:branchname = system("git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\n'")
    return strlen(l:branchname) > 0?'['.l:branchname.']':''
endfunction

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
" }}}

" Undo {{{2
set undodir=$HOME/.vim/undodir " Set folder to store undo files
set undofile                   " Allow persistent undo
set undolevels=1000            " Use many levels of undo
set history=1000               " Remember more commands and search history
" }}}

" Timeout {{{2
set timeout                    " Set a timeout to commands
set timeoutlen=1500            " Set timeout value to commands
" }}}

" Autocmd to have custom settings depending on file type {{{2

" matchpairs {{{3
autocmd FileType c,cpp,java setlocal matchpairs+==:; " Jump between the '=' and ';'
autocmd FileType html setlocal matchpairs+=<:>       " Adding a pair of <>
" }}}

" makeprg (for :make) {{{3
autocmd FileType c        setlocal makeprg=cc\ %\ $*
autocmd FileType python   nnoremap <F5> :term python -i %<CR> " Open a term with interactive python
autocmd FileType html     setlocal makeprg=$BROWSER\ %\ $*
autocmd FileType markdown setlocal makeprg=pandoc\ %\ $*\ \-o\ %.pdf
autocmd FileType markdown setlocal makeprg=pandoc\ %\ $*\ \-o\ %.pdf
autocmd FileType css      setlocal makeprg=npx\ prettier\ --write\ %
" }}}

" Markers {{{3
autocmd FileType python set foldmethod=indent
autocmd FileType go     set foldmethod=marker
autocmd FileType go     set foldmarker={,}
" }}}

" Proper comments (<leader>cc to comment, <leader>cu to uncomment, <Leader>c<space> to toggle) {{{3
autocmd FileType python,sh setlocal commentstring=#\ %s
autocmd FileType html      setlocal commentstring=<!--\ %s\ -->
autocmd FileType c         setlocal commentstring=/*\ %s\ */
autocmd FileType go        setlocal commentstring=//\ %s
autocmd FileType xdefaults setlocal commentstring=!\ %s
autocmd FileType vim       setlocal commentstring=\"\ %s
autocmd FileType sql       setlocal commentstring=--\ %s
" }}}

" Settings {{{3
autocmd FileType dockerfile set noexpandtab
autocmd FileType go         setlocal noet ts=4 sw=4 sts=4
autocmd FileType markdown   setlocal spell
autocmd FileType gitcommit  setlocal spell
autocmd FileType nginx      setlocal noet ts=4 sw=4 sts=4
augroup Binary                 " Display Bin files using xxd
  au!
  au BufReadPre  *.bin  let &bin=1
  au BufReadPost *.bin  if &bin | %!xxd
  au BufReadPost *.bin  set ft=xxd | endif
  au BufWritePre *.bin  if &bin | %!xxd -r
  au BufWritePre *.bin  endif
  au BufWritePost *.bin if &bin | %!xxd
  au BufWritePost *.bin set nomod | endif
augroup END
" }}}

" Path {{{3
autocmd FileType c,cpp setlocal path+=/usr/include include&
" }}}
" }}}

" Autocmd misc {{{2
" When editing a file, always jump to the last known cursor position.
" Don't do it when the position is invalid or when inside an event handler
" (happens when dropping a file on gvim).
" Also don't do it when the mark is in the first line, that is the default
" position when opening a file.
autocmd BufReadPost *
      \ if line("'\"") > 1 && line("'\"") <= line("$") |
      \	exe "normal! g`\"" |
      \ endif
" }}}
" }}}

" Bindings {{{1
" Save {{{2
nnoremap <Leader>w :update<CR> " <space>w writes a files only if modified
nnoremap <Leader><Leader> :update<CR>
" For when we forget to use sudo to open/edit a file
cmap w!! w !sudo tee % >/dev/null
" }}}

" Use <Leader>W to strip all trailing white spaces in the current file {{{2
nnoremap <Leader>W :%s/\s\+$//<CR>:let @/=''<CR>
" }}}

" Splitting window {{{2
nnoremap <F11> :split<CR>      " Do a horizontal split with <F11>
nnoremap <F12> :vsplit<CR>     " Do a vertical split with <F12>
" }}}

" Ctrl-jklm  changes to that split {{{2
map <c-j> <c-w>j               " Move cursor to down split
map <c-k> <c-w>k               " Move cursor to up split
map <c-l> <c-w>l               " Move cursor to right split
map <c-h> <c-w>h               " Move cursor to left split
" }}}

" windows like {{{2
nnoremap <C-c> "+y
nnoremap <C-v> "+p
nnoremap <C-s> :update<CR>
" }}}

" Auto make {{{2
nnoremap <F5> :make<CR><c-w>   " Auto make
" }}}

" Add ad matching char {{{2
imap ( ()<C-[>i
imap [ []<C-[>i
imap { {}<C-[>i
imap < <><C-[>i
" }}}


" Turn off search highlighting {{{2
nmap <leader>, :nohlsearch<CR>
" }}}

" Spell check {{{2
" z=    " Change word
" ]s    " Jump to next misspelled word
" zg    " Add a word to dictionary
" zw    " Mark a word misspelled
map <F6> :setlocal spell!<CR>

" Set dictionary (Its used with C-X C-K to auto complete words)
set dictionary=/usr/share/dict/words
" }}}

" Prettier files command {{{2
command! JsonPretty execute ":%!python -m json.tool"
" }}}

" Open Terminal (can use :vertical terminal) {{{2
nnoremap <F3> :terminal<CR>
" }}}
" }}}

" Plugins {{{1
execute pathogen#infect()
" Airline {{{2
let g:airline#extensions#tabline#enabled = 1
" }}}

" Adding markdown syntax highlighter {{{2
let g:markdown_fenced_languages = ['html', 'python', 'bash=sh']
let g:markdown_syntax_conceal = 0
let g:markdown_minlines = 100
" }}}

" Nerdtree {{{2
nnoremap <F1> :NERDTreeToggle<CR>
autocmd StdinReadPre * let s:std_in=1
" Open Nerdtree when no file is provided to vim
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
" }}}

" Nerdcommenter {{{2
let g:NERDSpaceDelims = 1
let g:NERDTreeShowHidden=1
let g:NERDCompactSexyComs = 1
let g:NERDTrimTrailingWhitespace = 1
let g:NERDTreeIgnore=['.*.swp', '*.o', '*.out', '*.pyc']
" }}}

" Multicursor {{{2
let g:multi_cursor_quit_key = '<Esc>'
" }}}

" CtrlP {{{2
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden -g ""'
" }}}

" supertab {{{2
" This allow to scoll auto complete top to bottom
let g:SuperTabDefaultCompletionType = "<c-n>"
" }}}

" ultisnips {{{2
" Create snippets using :UltiSnipsEdit
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<tab>"
let g:UltiSnipsJumpBackwardTrigger="<s-tab>"
let g:UltiSnipsEditSplit="vertical"
let g:UltiSnipsSnippetsDir = "~/.vim/UltiSnips/"
" }}}
" }}} vim: fdm=marker
