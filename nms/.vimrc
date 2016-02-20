" vim configuration for Kristian Lyngstol <kristian@bohemians.org>
" Basically just adjust for dark background, enable spell checking, and
" load a compiz-vimrc if we're working on compiz.

source /etc/vim/vimrc

filetype plugin on

" Hit "K" to look up something in man
runtime! ftplugin/man.vim

set helpheight=50
"""""""""""""""""""" Look and feel
" I'm almost always at a dark terminal. But meh.
set t_Co=88
set background=dark
"set background=light
" Make sure we have a sane amount of colors. Urxvt has 88 (normal 16,
" rgb-cube from 17 to 79, shades of grey from 80 to 88).

" Set tabs to show as normal, but add a visual indicator of trailing
" whitespace. Set list to make this sane. (Testing)
set lcs=tab:\ \ ,trail:.
"set lcs=tab:»\ ,precedes:<,trail:.
set list
				
" Show line numbers. Ensures that I don't get lost.
set nu

" Set smart title (hopefully)
" I don't use titles in screen, so pass them on to the terminal. (hack)
if &term == "screen"
  set t_ts=]2;
  set t_fs=
endif

" Set the title if possible
set title

" Always show a status line. This ensures that I know what I'm editing and
" always have column-numbers and general status ([+] etc).
set laststatus=2

set scrolloff=1

" All-important syntax highlighting
syntax on

" Some historic color stuff
hi DiffChange ctermbg=60
hi DiffAdd ctermbg=17
hi DiffText ctermbg=52
hi clear TabLine
hi TabLine cterm=reverse
hi TabLineSel ctermbg=29 ctermfg=15

" {} matching us ambiguous by default (in my head, at least)
hi MatchParen ctermbg=blue



"""""""""""""""""""" Coding style
" Always use smartindent. Use :set paste for pasting.
set smartindent

" Defines how stuff is indented:
" t = Auto-wrap at TW
" c = Auto-wrap at TW for comments and insert comment-leader
" q = Allow comment-formating with 'gq'
" r = Insert comment-leader on manual enter/return.
" o = Ditto for 'o'/'O' (do I even use that?)
" l = Don't break lines when they were too big to begin with.
set formatoptions=tcqrol

" tw of 75 works wonders on 80char-terminals (or heavily vsplit terms)
set tw=75

" Use modelines(ie: vim: set foo). This is a tad dangerous, as some idiots
" set all sorts of things. FIXME: Should fix this to only apply to certain
" directories.
set ml

" Most projects I work with use two levels of depth, so make a top-level
" tag-file. In other words:
" bin/varnishd/, include/ and lib/libvcl/ has the same tagfile.
set tag+=../../tags,../tags

set path+=../include,include,../../include

" Spell checking by default.
set spell

" Need to adjust the SpellBad hilight because I don't want it too
" aggressive, since it's often mistaken (in code). An underline is nice
" enough without being too obtrusive.
hi SpellBad NONE
hi SpellBad term=underline,undercurl cterm=undercurl
hi clear SpellCap

set cino=(0,t0
""""" Automatic tag/preview lookup.
" aka: insanity

" Backup every 1sec - the cursorhold is on the same timer.
set updatetime=1000

" Makes it bearable to use on a 80x25
set previewheight=5

" Change this to stop the insanity
let insanity = "ensue"

" au! CursorHold *.[ch] nested exe "silent! ptag " . expand("<cword>")
au! CursorHold *.{c,h,java} nested call PreviewWord()
func! PreviewWord()
  if &previewwindow			" don't do this in the preview window
    return
  endif
  if g:insanity != "ensue"
	return
  endif
  exe "silent! ptag " . expand("<cword>")
endfun

" Complete using the spell checker too
set complete+=kspell

" Complete as much as is unique - shell-style - instead of blindly
" completing the first match and requiring to re-issue commands.
set cot+=longest

" Ditto for menus (and list the alternatives) (and file browsing!) With
" seven hundred thousand files, it's then easier to complete the one in the
" middle.
set wildmode=list:longest
