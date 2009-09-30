" echo text with margins and colored parts
" File:         bbecho.vim
" Created:      2009 Mar 31
" Last Change:  2009 Jun 10
" Rev Days:     4
" Version:	0.1
" Author:	Andy Wokula <anwoku@yahoo.de>

" Description:
"   Echo a string in the command-line area, with wrapping at customizable
"   left and right margins.  The string can contain BBCode-like tags with a
"   highlight-group to switch the color for the following text.

" TODO
" - check multi-byte encodings!
" - wrap lines only at spaces (not before tags); quite hard to fix (need look
"   ahead on the next part; delay writing part's last screen line if
"   partspc_next == '' and next part does not start with a space after the
"   tag)
" - detect impossible margin values

" ~\code\trial\vim\more\test\D9823.vim

" Hints:
"   Example tag: "[Statement]"
"   Switch back to Normal color: "[None]" or "[Normal]"
"   Too long lines wrap at spaces and before '[' (the latter is a bug).
"   Special tag "[[]" to escape "[" (not always needed).
"	:call bbecho#Line(2, '[[]None]')
"	:call bbecho#Line(2, '[Unrecognized Tag]')
"   Unrecognized tags are kept as text.
"   Normal BBCode codes don't work.
"   No mixing of text styles -> no closing tags.

" Vim Hints:
"   The command ":hi" lists the currently available hl-groups.
"   :h highlight-groups
"   Highlight-groups are case insensitive.

" Customization:
" define shortcuts for highlight groups:
if !exists("g:bbecho_abbr")
    let g:bbecho_abbr = {}
endif
call extend(g:bbecho_abbr, {"n": "None", "u": "Underlined"}, "keep")

" Echo a multi-line {text}.  Colors: hl-group is init'ed and restored to
" "None".
func! bbecho#Text(leftmargin, text, ...) "{{{
    " leftmargin    (number)
    " a:1	    right margin (defaults to leftmargin)
    let rightmargin = a:0 >= 1 ? a:1 : a:leftmargin
    echohl None
    for line in split(a:text, "\n")
        call bbecho#Line(a:leftmargin, line, rightmargin)
    endfor
    echohl None
endfunc "}}}

" Echo one line of {text}.  There is no init or restoring of highlight
" groups.
func! bbecho#Line(leftmargin, text, ...) "{{{
    " {text}	string without line breaks "\n" (else undefined behaviour)
    "		and without tabs "\t" (else converted to spaces)

    let rightmargin = max([a:0 >= 1 ? a:1 : a:leftmargin, 1])
    let fillwidth = &columns - a:leftmargin - max([1, rightmargin])
    " start in a new screen line:
    echo ""
    let parts = split(substitute(a:text,'\t',' ','g'), '\ze\[\@<![')
    " tabs in the {text} don't work, just convert them to spaces
    if empty(parts)
	return
    endif

    let str_leftm = repeat(" ", a:leftmargin)
    let linelen = 0	" len of screen line so far (w/o margins)
    let newline = 1	" not sure yet if equiv to linelen==0
    let partspc = ''	" trailing spaces from the previous part
    let leftm_cmd = 'echo str_leftm'
    let hlcmd = ""

    for part in parts
	let lbrack = ""
	" start-of-text position after [tag]
	let sotpos = matchend(part, '^\[[^]]*]')
	if sotpos >= 2
	    let hlgroup = strpart(part, 1, sotpos-2)
	    let hlgroup = get(g:bbecho_abbr, hlgroup, hlgroup)
	    if hlID(hlgroup) >= 1 || hlgroup =~? '^None$'
		let hlcmd = "echohl ".hlgroup
		if hlgroup =~? '^None$'
		    let leftm_cmd = 'echo str_leftm'
		else
		    let leftm_cmd = 'echohl None|echo str_leftm|'. hlcmd
		endif
	    elseif hlgroup == '['
		let lbrack = '['
	    else
		" unrecognized tag: keep it in the text
		let sotpos = 0
	    endif
	endif

	" trailing spaces position:
	let tspos = match(part, ' \+$')
	if tspos >= 0
	    let text = lbrack. strpart(part, sotpos, tspos-sotpos)
	    let partspc_next = strpart(part, tspos)
	else
	    let text = lbrack. strpart(part, sotpos)
	    let partspc_next = ''
	endif
	" part == tag . text . partspc_next

	if !newline
	    " part's text continues existing text on the current screen line
	    let pslen = strlen(partspc)
	    let restwid = fillwidth - linelen - pslen
	    let tlen = strlen(text)
	    if tlen <= restwid
		echon partspc
		exec hlcmd
		echon text
		let linelen += pslen + tlen
		let newline = 0
		let partspc = partspc_next
		continue
	    endif

	    if restwid >= 1
		let pat1 = printf('^.\{0,%d}\S\S\@!', restwid-1)
		let text2pos = matchend(text, pat1)
		if text2pos >= 0
		    echon partspc
		    exec hlcmd
		    echon strpart(text, 0, text2pos). "\n"
		    let text = strpart(text, matchend(text, ' *', text2pos))
		endif
	    endif
	    if restwid <= 0 || text2pos < 0
		echo ""
		exec hlcmd
	    endif
	    let linelen = 0
	    let newline = 1
	else
	    exec hlcmd
	endif

	" part's text starts in a new screen line
	let tlen = strlen(text)
	if tlen <= fillwidth
	    " part's text fits in the screen line
	    exec leftm_cmd
	    echon text
	    let linelen = tlen
	    let newline = 0
	    let partspc = partspc_next
	    continue
	endif

	" part's text is longer than a screen line
	let rep = fillwidth - 1
	let splpat = printf('\%%(.\{1,%d}\S\S\@!\|.\{%d}\)\zs *', rep, rep)
	let scr_lines = split(text, splpat)
	let n_slines = len(scr_lines)
	let idx = 0
	while idx < n_slines-1
	    exec leftm_cmd
	    echon scr_lines[idx]
	    let idx += 1
	endwhile
	let text = scr_lines[-1]
	exec leftm_cmd
	echon text
	let linelen = strlen(text)	" strlen(substitute(text, '.', 'x', 'g'))
	let newline = 0
	let partspc = partspc_next
    endfor
endfunc "}}}

" vim:set fdm=marker noet ts=8 sw=4 sts=4:
