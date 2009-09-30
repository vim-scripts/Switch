" Vim plugin -- Quickly toggle boolean options
" File:		switch.vim
" Created:	2009 Jun 06
" Last Change:	2009 Jun 11
" Rev Days:	4
" Author:	Andy Wokula <anwoku@yahoo.de>
" Version:	1.00
"		rewrite of v0.12 from 2008 Aug 08, by Tomas RC,
"		univrc@gmail.com, http://univrc.org/
" Dependencies: autoload/bbecho.vim

" Usage: {{{
"   Press  Ctrl-Q  to show the ":switch" prompt.  Possible arguments:
"
"   {optkey}		toggle an option value
"   Tab			list option keys
"   <Enter> {optkey}	open the help page of an option
"   Ctrl-Q {optkey}	show the value of an option
"   <F1>		print usage
"
"   If the prompt changes to ":", you are back in Cmdline mode.  This
"   happens after pressing ":", CTRL-U or Backspace.

" }}}
" Change Active Options: {{{
" (1) create your own set of options:
"	:let g:switch_options = "e:expandtab,l:list"
"
" (2) use default options, and remove or add keys:
"	:let g:switch_options = ".,c,d,i:ignorecase"
"   (variable must start with ".,")
"
" (3) go back to default options:
"	:let g:switch_options = ""
"
" - each entry is {optkey}:{option}
" - each {optkey} should be a single letter (not a multi-byte key)
" NEW: white space between entries is not ignored, you can now use " " for
"      {optkey}
" }}}

" Script Init {{{
if exists('loaded_switch')
    finish
endif
let loaded_switch = 1

if v:version < 700 || &cp
    echomsg "Switch: you need at least Vim 7.0 and 'nocp' set"
    finish
endif

let s:sav_cpo = &cpo
set cpo&vim
"}}}

" Config Variables: {{{
" All these variables can be changed during session!

if !exists("g:switch_options")
    let g:switch_options = ""
endif

if !exists("g:switch_help_header")
    let g:switch_help_header = 1
endif

if !exists("g:switch_help_leftalign")
    let g:switch_help_leftalign = 0
endif

if !exists("g:switch_non_bool")
    let g:switch_non_bool = {}
endif
call extend(g:switch_non_bool, {
    \ "ve_all": 'virtualedit value all',
    \ "go_menu": 'guioptions flag m',
    \ "tw_vimmail": "textwidth value 76 72",
    \}, "keep")

" g:switch_input_map
"}}}

" Mappings:  {{{
if !hasmapto("<Plug>SwitchOption")
    map  <unique> <C-Q> <Plug>SwitchOption
    map! <unique> <C-Q> <Plug>SwitchOption
endif

map		<Plug>SwitchOption <SID>swopt
imap <script>	<Plug>SwitchOption <C-O><SID>swopt
cmap <script>	<Plug>SwitchOption <C-\><C-N><SID>swopt

noremap <script><silent> <SID>swopt <SID>:<C-U>call <SID>Switch()<CR>
noremap <expr> <SID>: <sid>gvmap_mode()
"}}}

func! <sid>Switch() "{{{
    call s:gvmap_restore()

    call s:GetUserSettings()

    let s:prompt = ":switch "
    echo s:prompt
    let s:displayed = 1
    let sav_more = &more
    set nomore
    let state = "start"
    while state != "end"
	let [fa_input, char] = s:Input()
	let [action, state] = s:Trans(state, fa_input)
	call s:Do_{action}(char)
    endwhile
    let &more = sav_more

    " workaround for display bug: do a redraw when toggling 've':
    if mode() == "\<C-V>"
	call feedkeys("oo", "n")
    endif
endfunc "}}}

"" Mealy Stuff {{{
" Finite Automaton (FA)
"
" states
"   "start"	after CTRL-Q, waiting for {optkey} to toggle an option
"   "help"	after CTRL-Q <Enter>, waiting for {optkey} to show help
"   "get"	after CTRL-?, waiting for {optkey} to show the current value
"   "end"	end state

" INPUT FOR THE FA (fa_input)
"		what the user typed:
"   "option"	option key
"   "complet"	tab or space
"   "opthelp"	help key F1
"   "optvalue"	key to show the value
"   "colon"	:
"   "back"	backspace
"   "usage"
"   "other"	any other key

" actions
"   "Toggle"	    toggle an option
"   "HelpPrompt"    show help prompt
"   "Help"	    do :h 'option'
"   "PrintList"	    show list of switch options
"   "Cmdline"	    goto to Cmdline mode
"   "ShowValue"	    print option value
"   "Quit"	    no-op (after pressing a key that does nothing)

"}}}
" s:Variables {{{

" s:displayed	    1 nothing displayed, 2 option list, 3 usage (more are
"		    possible: 5, 7, 11, 13, ...)
"   If 1, :redraw (to avoid the hit-enter prompt), else don't :redraw (to
"   keep lists displayed).  The idea is to do a :redraw if the same list is
"   going to appear twice on screen, whereas option list and usage fit well
"   together.

" s:notesc
let s:notesc = '\%(\\\@<!\%(\\\\\)*\)\@<='

" default options
let s:default_options =
    \ "A:autochdir,B:scrollbind,C:cursorcolumn,H:hidden,I:infercase"
    \.",L:cursorline,M:showmode,P:wrapscan,S:showcmd,W:autowrite"
    \.",a:autoindent,b:linebreak,c:ignorecase,d:diff,e:expandtab,h:hlsearch"
    \.",i:incsearch,j:joinspaces,k:backup,l:list,m:modifiable,g:{go_menu}"
    \.",n:number,p:paste,r:readonly,s:spell,t:{tw_vimmail},v:{ve_all},w:wrap"
    \.",z:lazyredraw"
let s:old_options = "~(_8(I)"
"}}}

" FA input map {{{
" map keys typed by the user to input for the FA
if !exists("g:switch_input_map")
    let g:switch_input_map = {}
endif
call extend(g:switch_input_map, {
    \ "\<F1>": "usage",
    \ "\t": "complet", " ": "complet",
    \ "?": "optvalue", "\<C-Q>": "optvalue",
    \ "\r": "opthelp",
    \ ":": "colon", "\<C-U>": "colon",
    \ "\<BS>": "back",
    \}, "keep")
" }}}
func! s:Input() "{{{
    let chr = s:Getchar()
    " if a letter is mapped for an option AND for an action, the option
    " has precedence
    if has_key(s:active_options, chr)
	return ["option", chr]
    endif
    let fa_input = get(g:switch_input_map, chr, "")
    if fa_input != ""
	return [fa_input, chr]
    endif
    if chr =~ '^\w$'
	" unmapped letter ... checked again later
	return ["option", chr]
    endif

    let sav_dy = &dy
    set display-=uhex
    try
	let tryctrl = tr(strtrans(chr),"@M","J ")
	if strlen(tryctrl)==2 && tryctrl[0] == "^"
	    let chr = tolower(tryctrl[1])
	    if has_key(s:active_options, chr)
		return ["option", chr]
	    endif
	    let chr = toupper(tryctrl[1])
	    if has_key(s:active_options, chr)
		return ["option", chr]
	    endif
	endif
    finally
	let &dy = sav_dy
    endtry

    return ["other", chr]
endfunc "}}}

" FA Trans Table {{{
let s:fa_table = {}
let s:fa_table.start = {
    \ "option": "Toggle end",
    \ "complet": "PrintList start",
    \ "usage": "Usage start",
    \ "opthelp": "HelpPrompt help",
    \ "optvalue": "GetPrompt get",
    \ "back": "Cmdline end",
    \}
let s:fa_table.help = {
    \ "option": "Help end",
    \ "complet": "PrintList help",
    \ "usage": "Usage help",
    \ "optvalue": "GetPrompt get",
    \ "back": "SwitchPrompt start",
    \}
let s:fa_table.get = {
    \ "option": "ShowValue end",
    \ "complet": "PrintList get",
    \ "usage": "Usage get",
    \ "opthelp": "HelpPrompt help",
    \ "back": "SwitchPrompt start",
    \}
" }}}
func! s:Trans(state, fa_input) "{{{
    let trone = s:fa_table[a:state]
    if has_key(trone, a:fa_input)
	return split(trone[a:fa_input])
    elseif a:fa_input == "colon"
	return ["Cmdline", "end"]
    endif
    return ["Quit", "end"]
endfunc "}}}

func! s:Getchar() "{{{
    let chr = getchar()
    return chr != 0 ? nr2char(chr) : chr
endfunc "}}}
func! s:Redraw(...) "{{{
    if s:displayed == 1 || a:0 >= 1 && a:1
	redraw
	let s:displayed = 1
    endif
    " extra function, makes it easier to skip redrawing when :debugging
endfunc "}}}

" Actions:
func! s:Do_Toggle(char) "{{{
    let optname = get(s:active_options, a:char, "")
    if optname == ""
	call s:Warning('Key "%s" is not mapped', strtrans(a:char))
    elseif optname =~ '^{\w\+}$'
	call s:ToggleNonBoolean(matchstr(optname, '\w\+'))
    elseif exists("+". optname)
	call s:Redraw(1)
	exec "setlocal" optname."!" optname."?"
    else
	call s:Warning("Not a working option: '%s'", optname)
    endif
endfunc "}}}
func! s:Do_ShowValue(char) "{{{
    let optname = get(s:active_options, a:char, "")
    if optname == ""
	return
    elseif optname =~ '^{\w\+}$'
	call s:ShowValueNonBoolean(matchstr(optname, '\w\+'))
    elseif exists("+". optname)
	call s:Redraw(1)
	exec "setlocal" optname."?"
    endif
endfunc "}}}
func! s:Do_HelpPrompt(...) "{{{
    call s:Redraw()
    let s:prompt = ":switch help "
    echo s:prompt
endfunc "}}}
func! s:Do_Help(char) "{{{
    let optname = get(s:active_options, a:char, "")
    if optname == ""
	return
    elseif optname =~ '^{\w\+}$'
	call s:HelpNonBoolean(matchstr(optname, '\w\+'))
    else
	exec "help '". optname."'"
    endif
endfunc "}}}
func! s:Do_PrintList(...) "{{{
    " toggle display of options list
    if s:displayed % 2 == 0
	call s:Redraw(1)
    else
	if g:switch_help_header
	    call s:HelpHeader()
	endif
	call Switch_PrintOptions()
	let s:displayed = s:displayed * 2
    endif
    echo s:prompt
endfunc "}}}
func! s:Do_Cmdline(...) "{{{
    call feedkeys(":")
endfunc "}}}
func! s:Do_GetPrompt(...) "{{{
    call s:Redraw()
    let s:prompt = ":switch value? "
    echo s:prompt
endfunc "}}}
func! s:Do_Quit(...) "{{{
    call s:Redraw(1)
endfunc "}}}
func! s:Do_SwitchPrompt(...) "{{{
    " let s:displayed = 1
    call s:Redraw()
    let s:prompt = ":switch "
    echo s:prompt
endfunc "}}}
func! s:Do_Usage(...) "{{{
    " toggle display of usage
    if s:displayed % 3 == 0
	call s:Redraw(1)
    else
	call bbecho#Text(4, "[PreProc]Keys:[n]\n"
	    \. "[Special]{optkey}[n]         toggle option value\n"
	    \. "[Special]Tab[n]              print a list of option keys [Type]{optkey} : {option}[n]\n"
	    \. "[Special]Enter {optkey}[n]   open the [Constant]help[n] page of an option\n"
	    \. "[Special]? {optkey}[n]       show the [Constant]value[n] of an option\n"
	    \. "[Special]CTRL-Q {optkey}[n]  dito\n"
	    \. "[Special]:[n] or [Special]CTRL-U[n]      go to Command-line mode\n"
	    \. "[Special]Backspace[n]        delete the last word"
	    \)
	echo "\n"
	let s:displayed = s:displayed * 3
    endif
    echo s:prompt
endfunc "}}}

func! s:HelpHeader() "{{{
    call bbecho#Line(4,
	\  "[PreProc]Help:[n] Table columns display [Special]{optkey}[n] : {option}."
	\. "  Press [Special]<F1>[n] for help on usage."
	\. "  The list displays the current value of each option.")
    echo "\n"
endfunc "}}}
func! Switch_PrintOptions() "{{{
    call s:GetUserSettings()

    let nentries = len(s:active_options)
    let maxoptlen = 2 + max(map(values(s:active_options),'strlen(v:val)'))
    let colwidth = 2 + 1 + 3 + maxoptlen + 2
    let ncolumns = (&columns-1) / colwidth
    if ncolumns > 0
	let nlines = nentries / ncolumns + (nentries % ncolumns > 0)
	if g:switch_help_leftalign
	    let prewidth = 0
	else
	    if nlines > 1
		let ncolumns = nentries / nlines + (nentries % nlines > 0)
		let prewidth = ((&columns-1) - ncolumns*colwidth) / 3
	    else
		" the old setting, slightly wrong
		let prewidth = (&columns-1) % colwidth / 3
	    endif
	endif
	let prespaces = repeat(" ", prewidth)
	let fmtstr = "  %s : %.". maxoptlen. "s  "
    else
	let ncolumns = 1
	let nlines = nentries
	let prespaces = ""
	let fmtstr = "%s : %.". maxoptlen. "s"
    endif

    let list = []
    for entry in items(s:active_options)
	call add(list, [entry[1], entry[0]])
    endfor
    call sort(list)

    let filler = repeat(" ", maxoptlen)
    let lidx = 0
    while lidx < nlines
	let line = prespaces
	let cidx = lidx
	while cidx < nentries
	    let entry = list[cidx]
	    let optn = entry[0]
	    try
		let no = optn=~'^{' || eval("&".optn) ? "  " : "no"
	    catch
		echohl ErrorMsg
		echo "Unknown option:" optn
		echohl None
		let no = "! "
	    endtry
	    let line .= printf(fmtstr, entry[1], no.optn.filler)
	    let cidx += nlines
	endwhile
	echo line
	let lidx += 1
    endwhile
    echo "\n"
    " not a bug: it is normal if not all columns are used
endfunc "}}}

func! s:GetUserSettings() "{{{
    if s:old_options == g:switch_options
	return
    endif
    let s:old_options = g:switch_options
    let s:active_options = {}
    let modify = g:switch_options =~ '^\.,'
    if modify || g:switch_options == ""
	for flagmap in split(s:default_options, ',')
	    let parsed = matchlist(flagmap, '^\(.[^:]*\):\(\a\{2,}\|{\w\+}\)')
	    if !empty(parsed)
		let s:active_options[parsed[1]] = parsed[2]
	    endif
	endfor
	if modify
	    let g:switch_options = substitute(g:switch_options, '^\.,','','')
	endif
    endif
    if g:switch_options != ""
	for flagmap in split(g:switch_options, ',')
	    let parsed = matchlist(flagmap, '^\(.[^:]*\):\(\a\{2,}\|{\w\+}\)')
	    if !empty(parsed)
		let s:active_options[parsed[1]] = parsed[2]
	    else
		let rmkey = matchstr(flagmap, '^.[^: \t]*')
		sil! unlet s:active_options[rmkey]
	    endif
	endfor
    endif
    if modify
	let g:switch_options = s:old_options
    endif
endfunc "}}}

func! s:ToggleNonBoolean(refname) "{{{
    if !has_key(g:switch_non_bool, a:refname)
	" call s:Warning('g:switch_non_bool: Missing key "%s"', a:refname)
        let g:switch_non_bool[a:refname] = "opt_dummy cmd_dummy val_dummy ..."
    endif
    let defstr = g:switch_non_bool[a:refname]
    try
	let [optname, cmd; values] = split(defstr, s:notesc.' ', 1)
    catch
	call s:Warning('g:switch_non_bool.%s must be "{opt} {cmd} {val} ..." ', a:refname)
	return
    endtry
    if !exists("+". optname)
        call s:Warning("not a working option: '%s'", optname)
        return
    endif
    if empty(values)
        call s:Warning('g:switch_non_bool.%s needs some values to toggle', a:refname)
        return
    endif
    let val0 = values[0]

    if cmd ==? "value"
	if type(eval("&". optname)) == 0
	    call map(values, '0 + v:val')
        elseif len(values) == 1
            call add(values, "")
	endif
	let idx = index(values, eval("&". optname))
	if idx >= 0
	    exec "setl" optname."=". values[(idx+1) % len(values)]
	else
	    exec "setl" optname."=". val0
	endif

    elseif cmd ==? "flag"
	if eval("&". optname) =~# val0
	    exec "setl" optname."-=". val0
	else
	    exec "setl" optname."+=". val0
	endif

    else
	call s:Warning('g:switch_non_bool.%s:'.
	    \ ' replace "%s" with either "value" or "flag"', a:refname, cmd)
	return

    endif
    call s:Redraw(1)
    exec "setl" optname."?"
endfunc "}}}
func! s:ShowValueNonBoolean(refname) "{{{
    if !has_key(g:switch_non_bool, a:refname)
	" error
	return
    endif
    let optname = split(g:switch_non_bool[a:refname])[0]
    if exists("+". optname)
	call s:Redraw(1)
	exec "setl" optname."?"
    endif
endfunc "}}}
func! s:HelpNonBoolean(refname) "{{{
    if !has_key(g:switch_non_bool, a:refname)
	" error
	return
    endif
    let optname = split(g:switch_non_bool[a:refname])[0]
    exec "help '". optname."'"
endfunc "}}}

" from autoload/gvmap.vim
func! <sid>gvmap_mode() "{{{
    let s:lastmode = mode()
    return ":"
endfunc "}}}
func! s:gvmap_restore() "{{{
    if exists("s:lastmode") && s:lastmode =~ "[vV\<C-V>]"
	normal! gv
	unlet s:lastmode
    endif
endfunc "}}}

func! s:Warning(fmt, ...) "{{{
    echohl WarningMsg
    echomsg "Switch:" call("printf", [a:fmt] + a:000)
    echohl None
endfunc "}}}

" Modeline: {{{1
let &cpo = s:sav_cpo

" press any key to continue, press any other key to quit
" vim:set fdm=marker ts=8:
