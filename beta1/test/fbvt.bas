   10 REM > FBVT - the driver that exercises FBVDU
   20 REM
   30 REM Load the engine first, then this, then RUN:
   40 REM   *EXEC FBVDU
   50 REM   *EXEC FBVT
   60 REM   RUN
   70 REM
   80 REM The geometry lives here, not in the engine, because it is the
   90 REM driver's decision: 80x64 on the glass, a grid small enough to
  100 REM print on a 6502 under b-em in simulation, 80x24 for the phase 3
  110 REM replays against pyte.
  120 :
  130 cols%=80:rows%=64
  140 cw%=8:ch%=8
  150 md%=21:vdu%=1:pivdu%=2
  160 rf$="RESVDU"
  170 rf%=0
  180 :
  190 REM sim% points the renderer at a DIMmed block instead of the
  200 REM framebuffer, loads the font from PIFONT instead of harvesting
  210 REM it, and dumps the result as characters. Everything between -
  220 REM the cell blit, the damage compare, the flush, the scroll, the
  230 REM cursor, the attributes - is the same code on the same path.
  240 REM
  250 REM So the engine can be exercised under b-em on a 6502 in seconds.
  260 REM 2.3a said the edit-test loop was the thing worth protecting and
  270 REM this is what protects it for phase 2, where the VT semantics
  280 REM arrive and the bugs will be in logic rather than in pixels.
  290 sim%=FALSE
  300 REM glass% is the second axis. sim% chooses where the pixels go -
  310 REM the framebuffer or a DIMmed block - and glass% chooses whether
  320 REM there are any. With glass%=FALSE there is no framebuffer, no
  330 REM font and no blitter, only the cell model, and the flush counts
  340 REM the damage it would have painted. That is the mode the phase 3
  350 REM replays run in: an 80x24 model is 15K, but an 80x24 framebuffer
  360 REM at 8x8 would be 120K and there is nowhere to put it.
  370 glass%=TRUE
  380 IF sim% THEN cols%=9:rows%=3
  390 :
  400 ON ERROR PROCerr:END
  410 PROCv_boot
  420 IF vfail$<>"" THEN PROCstop(vfail$)
  430 PROCtest
  440 END
  450 :
  460 REM ================ self test ================
  470 REM Everything above is the engine. Everything below exercises it
  480 REM and writes the timings to the share, because a screen that
  490 REM looks right is not a measurement.
10000 DEF PROCtest
10010 LOCAL n%,t1,t2,t3,t4
10020 PROCopen
10030 PROCw("[fbvdu1]")
10040 PROCw("run="+STR$(TIME))
10050 PROCw("geometry="+STR$(cols%)+"x"+STR$(rows%)+" cell="+STR$(cw%)+"x"+STR$(ch%))
10060 PROCw("screen=&"+STR$~fb%+" pitch="+STR$(pit%))
10070 :
10080 PROCpage1
10090 T=TIME:n%=FNv_flush:t1=TIME-T
10100 PROCw("full_flush_cs="+STR$(t1)+" painted="+STR$(n%))
10110 IF sim% THEN PROCv_dump("--- page 1, "+STR$(n%)+" cells painted")
10120 PROCv_ask("p1_palette","Palette strip: are all 256 patches different? (Y/N)","YN")
10130 PROCv_ask("p1_ansi","Are the 16 ANSI text lines 16 different colours? (Y/N)","YN")
10140 PROCv_ask("p1_box","Do the box pieces form a closed rectangle? (Y/N)","YN")
10150 PROCv_ask("p1_cursor","Is there a solid cursor block below the box? (Y/N)","YN")
10160 PROCwait
10170 :
10180 PROCv_text(2,rows%-2,"one cell changed, then flushed again",7,0,0)
10190 T=TIME:n%=FNv_flush:t2=TIME-T
10200 PROCw("small_flush_cs="+STR$(t2)+" painted="+STR$(n%))
10210 IF sim% THEN PROCw("damage_only="+STR$(n%)+" of "+STR$(cols%*rows%))
10220 PROCwait
10230 :
10240 PROCpage2
10250 T=TIME:n%=FNv_flush:t3=TIME-T
10260 PROCw("attr_flush_cs="+STR$(t3)+" painted="+STR$(n%))
10270 IF sim% THEN PROCv_dump("--- page 2, attributes")
10280 PROCv_ask("p2_attr","Bold, reverse, underline, strike - all four right? (Y/N)","YN")
10290 PROCv_ask("p2_ink","Are the coloured pairs legible, 196 on 17 and the rest? (Y/N)","YN")
10300 PROCwait
10310 :
10320 PROCpage3
10330 IF NOT sim% THEN n%=FNv_flush
10340 IF NOT sim% THEN PROCw("page3_painted="+STR$(n%))
10350 PROCv_ask("p3_dec","Do the DEC pieces draw ONE unbroken box? (Y/N)","YN")
10360 PROCv_ask("p3_utf8","Does the UTF-8 box below it look identical? (Y/N)","YN")
10370 PROCv_ask("p3_bar","Does the reverse bar reach the RIGHT EDGE? (Y/N)","YN")
10380 PROCv_ask("p3_notch","Is the bar solid, with no gap at its right end? (Y/N)","YN")
10390 PROCwait
10400 :
10410 PROCcurtest
10420 IF sim% THEN PROCsimscroll ELSE PROChwscroll
10430 :
10440 PROCw("[end]")
10450 PROCshut
10460 VDU 23,1,1
10470 VDU 26:CLS
10480 PRINT "FBVDU phase 1 self test done - ";rf$;" is on the share."
10490 ENDPROC
10500 :
10510 REM A page that uses the whole palette, because 256 exact colours
10520 REM is the thing Phase 0 bought and it should be visible.
10530 DEF PROCpage1
10540 LOCAL i%,x%,y%
10550 PROCv_cls(7,0)
10560 IF sim% THEN PROCsimpage1:ENDPROC
10570 PROCv_text(2,1,"FBVDU - the renderer owns these pixels",15,0,0)
10580 PROCv_text(2,2,"no VDU driver, no OSWRCH, no GCOL",8,0,0)
10590 FOR i%=0 TO 255
10600   x%=2+(i% MOD 64):y%=5+(i% DIV 64)
10610   PROCv_put(x%,y%,32,0,i%,0)
10620 NEXT
10630 PROCv_text(2,10,"256 palette entries, set to the xterm colours",7,0,0)
10640 FOR i%=0 TO 15
10650   PROCv_text(2,12+i%,"ANSI "+STR$(i%)+"  the quick brown fox",i%,0,0)
10660 NEXT
10670 PROCv_text(2,29,"box pieces, synthesised with VDU 23 and harvested:",7,0,0)
10680 PROCv_put(2,30,224,15,0,0):PROCv_put(3,30,228,15,0,0):PROCv_put(4,30,225,15,0,0)
10690 PROCv_put(2,31,229,15,0,0):PROCv_put(4,31,229,15,0,0)
10700 PROCv_put(2,32,226,15,0,0):PROCv_put(3,32,228,15,0,0):PROCv_put(4,32,227,15,0,0)
10710 PROCv_goto(2,34):cvis%=TRUE
10720 ENDPROC
10730 :
10740 REM Everything phase 2 and phase 3 added that can only be judged on the
10750 REM glass. The DEC line drawing set is written into font% slots 128-159
10760 REM by PROCv_glyphs and has NEVER been rendered on hardware; the UTF-8
10770 REM box below it goes through FNv_uni to the same slots, so the two rows
10780 REM must be indistinguishable. The reverse bar is phase 3's two bugs
10790 REM made visible: it is written by the ENGINE, through PROCv_write, as
10800 REM 80 reverse characters followed by a colour reset and an EL - the
10810 REM exact sequence top sends. If the bar stops short of the right edge
10820 REM the rendition is not surviving the erase; if it reaches the edge
10830 REM with a one-cell gap, the pending wrap is erasing the last cell.
10840 DEF PROCpage3
10850 LOCAL y%,i%,e$
10860 REM Hardware only. It needs seventeen rows and the simulated grid is
10870 REM 9x3, and PROCv_glyph does NOT bounds check - it trusts the parser,
10880 REM which clamps cx% and cy% on every path that sets them. A driver
10890 REM placing the cursor by hand does not, and writing past the end of
10900 REM scr% corrupted BASIC's variable table into "Unknown or missing
10910 REM variable" somewhere else entirely.
10920 IF sim% THEN ENDPROC
10930 PROCv_cls(7,0)
10940 e$=CHR$(27)
10950 PROCv_text(2,1,"phase 2: DEC line drawing, then the same box in UTF-8",7,0,0)
10960 y%=3
10970 PROCv_put(4,y%,141,7,0,0)
10980 FOR i%=5 TO 20:PROCv_put(i%,y%,146,7,0,0):NEXT
10990 PROCv_put(21,y%,140,7,0,0)
11000 PROCv_put(4,y%+1,153,7,0,0):PROCv_put(21,y%+1,153,7,0,0)
11010 PROCv_put(4,y%+2,142,7,0,0)
11020 FOR i%=5 TO 20:PROCv_put(i%,y%+2,146,7,0,0):NEXT
11030 PROCv_put(21,y%+2,139,7,0,0)
11040 :
11050 REM The same box, but reached the way a UTF-8 stream reaches it.
11060 cx%=4:cy%=y%+4
11070 PROCv_writes(FNu(&250C)+STRING$(16,"-")+FNu(&2510))
11080 cx%=4:cy%=y%+5:PROCv_writes(FNu(&2502))
11090 cx%=21:cy%=y%+5:PROCv_writes(FNu(&2502))
11100 cx%=4:cy%=y%+6
11110 PROCv_writes(FNu(&2514)+STRING$(16,"-")+FNu(&2518))
11120 FOR i%=5 TO 20:PROCv_put(i%,y%+4,146,7,0,0):PROCv_put(i%,y%+6,146,7,0,0):NEXT
11130 :
11140 PROCv_text(2,y%+9,"phase 3: the reverse bar top draws, written through the engine",7,0,0)
11150 cx%=0:cy%=y%+11
11160 PROCv_writes(e$+"[7m"+"  A FULL WIDTH REVERSE BAR, EXACTLY AS TOP SENDS IT"+STRING$(28," ")+e$+"[m"+e$+"[K")
11170 PROCv_text(2,y%+13,"it must reach the right edge, and have no gap at the end",7,0,0)
11180 PROCv_writes(e$+"[m")
11190 ENDPROC
11200 :
11210 REM A codepoint as its UTF-8 bytes, so the engine decodes it for real
11220 REM rather than being handed the answer.
11230 DEF FNu(u%)
11240 IF u%<&800 THEN =CHR$(&C0+u% DIV 64)+CHR$(&80+(u% AND 63))
11250 =CHR$(&E0+u% DIV 4096)+CHR$(&80+((u% DIV 64) AND 63))+CHR$(&80+(u% AND 63))
11260 :
11270 REM The attributes a terminal applies to any glyph, none of which
11280 REM the BBC VDU driver can do at all.
11290 REM The cursor is drawn at the end of a flush and erased at the start of
11300 REM the next one, with a whole drain of bytes in between - so it must be
11310 REM erased where it was DRAWN, not where the cursor is now. Erasing the
11320 REM wrong cell leaves the old one inverted on a glass whose shadow says
11330 REM it is already correct, and the flush can never remove it.
11340 REM
11350 REM Read back off the glass, because that is the only place the fault
11360 REM exists: the model and the shadow agree with each other perfectly
11370 REM while the pixels are wrong. In simulation the glass is a DIMmed
11380 REM block and can be read; on hardware this is what p1_cursor looks at.
11390 DEF PROCcurtest
11400 LOCAL n%,y%,l%,i%,r%,bad%
11410 PROCv_cls(7,0)
11420 n%=FNv_flush
11430 cvis%=TRUE
11440 REM Three flushes with the cursor somewhere different each time, which
11450 REM is what a drain of bytes does to it. Positions inside the grid at
11460 REM either geometry - the simulated one is 9x3.
11470 PROCv_goto(1,0):n%=FNv_flush
11480 PROCv_goto(cols%-2,1):n%=FNv_flush
11490 PROCv_goto(cols% DIV 2,2):n%=FNv_flush
11500 cvis%=FALSE:n%=FNv_flush
11510 REM Every cell is a blank in the same colours, so every pixel of those
11520 REM rows must be background. Anything else is a cursor never erased.
11530 REM Read off the GLASS: the model and the shadow agree with each other
11540 REM perfectly while the pixels are wrong, so neither can see it.
11550 bad%=0
11560 FOR y%=0 TO 2
11570   FOR l%=0 TO ch%-1
11580     r%=fb%+(y%*ch%+l%)*pit%
11590     FOR i%=0 TO cols%*cw%-4 STEP 4
11600       IF r%!i%<>0 THEN bad%=bad%+1
11610     NEXT
11620   NEXT
11630 NEXT
11640 PROCw("cursor_stale="+STR$(bad%))
11650 IF bad%=0 THEN PROCw("cursor_erase=OK") ELSE PROCw("cursor_erase=STALE")
11660 ENDPROC
11670 :
11680 DEF PROCpage2
11690 PROCv_cls(7,0)
11700 IF sim% THEN PROCsimpage2:ENDPROC
11710 PROCv_text(2,1,"attributes, drawn by the renderer not the font",15,0,0)
11720 PROCv_text(2,3,"plain",7,0,0)
11730 PROCv_text(2,4,"bold - the bright half of the ANSI 16",7,0,4)
11740 PROCv_text(2,5,"reverse",7,0,1)
11750 PROCv_text(2,6,"underline",7,0,2)
11760 PROCv_text(2,7,"strikethrough",7,0,8)
11770 PROCv_text(2,8,"reverse and underline together",7,0,3)
11780 PROCv_text(2,10,"true colour, no reduction:",7,0,0)
11790 PROCv_text(2,11,"196 on 17",196,17,0)
11800 PROCv_text(2,12,"46 on 232",46,232,0)
11810 PROCv_text(2,13,"226 on 18, underlined",226,18,2)
11820 PROCv_goto(30,13):cvis%=TRUE
11830 ENDPROC
11840 :
11850 REM Under b-em there is nobody to press a key, and GET would hang
11860 REM until the harness timed the run out.
11870 REM 9 x 3 cells. Small for two reasons. Everything has to fit in a
11880 REM 6502 co-processor's 30K of BASIC space alongside a 600-line
11890 REM program - the simulated framebuffer alone is cols x cw x rows x
11900 REM ch bytes, and 16 x 4 stopped fitting once the program grew - and
11910 REM nine columns is 72 pixels, so a dumped row does not wrap at 80.
11920 DEF PROCsimpage1
11930 PROCv_text(0,0,"Ag",15,0,0)
11940 PROCv_put(3,0,229,15,0,0)
11950 PROCv_put(4,0,228,15,0,0)
11960 PROCv_text(0,1,"bo",7,0,4)
11970 PROCv_goto(4,1):cvis%=TRUE
11980 ENDPROC
11990 :
12000 DEF PROCsimpage2
12010 PROCv_text(0,0,"rv",7,0,1)
12020 PROCv_text(3,0,"un",7,0,2)
12030 PROCv_text(6,0,"st",7,0,8)
12040 PROCv_text(0,1,"ink",3,1,0)
12050 cvis%=FALSE
12060 ENDPROC
12070 :
12080 REM The scroll holds one invariant: the glass, the model and the
12090 REM shadow all move together, so afterwards the ONLY damage is in
12100 REM the row the scroll exposed. Everything above it is already
12110 REM correct on the glass and must not be repainted.
12120 REM
12130 REM Not "the exposed row costs cols% cells" - that was the first
12140 REM version of this assertion and it was wrong. The old bottom row
12150 REM here is "row 3 abcdefg", which contains two spaces, and a space
12160 REM in the same colours is byte-identical to a blank cell, so two
12170 REM of its sixteen cells rightly need no repaint. Counting damage
12180 REM by row says what is meant; counting it in total does not.
12190 REM
12200 REM Every row is filled first. An earlier version scrolled a screen
12210 REM whose lower rows were already blank, which passes the invariant
12220 REM trivially and proves nothing.
12230 DEF PROCsimscroll
12240 LOCAL i%,n%,above%,below%
12250 FOR i%=0 TO rows%-1
12260   PROCv_text(0,i%,"r"+STR$(i%)+" abcdef",7,0,0)
12270 NEXT
12280 cvis%=FALSE
12290 n%=FNv_flush
12300 PROCv_dump("--- filled, "+STR$(n%)+" painted")
12310 PROCv_scroll(0,rows%-1,1,7,0)
12320 above%=FNv_damage(0,rows%-2)
12330 below%=FNv_damage(rows%-1,rows%-1)
12340 PROCw("scroll1_above="+STR$(above%)+" exposed_row="+STR$(below%))
12350 IF above%=0 THEN PROCw("scroll1=pass") ELSE PROCw("scroll1=FAIL damage above the exposed row")
12360 n%=FNv_flush
12370 PROCv_dump("--- one scroll: "+STR$(above%)+" damaged above, "+STR$(below%)+" in the exposed row")
12380 ENDPROC
12390 :
12400 REM Ten full-screen scrolls, timed, and then the invariant checked
12410 REM on the hardware rather than only in simulation: the bottom ten
12420 REM rows are what the scrolls exposed, and everything ABOVE them
12430 REM must already be correct on the glass. Damage there would mean
12440 REM the pixels, the model and the shadow had come out of step, and
12450 REM the shadow would then stop the flush from ever putting it right.
12460 REM
12470 REM The exposed rows are expected to be dirty, and by more than they
12480 REM look. Nothing clears them as the screen moves, so each scroll
12490 REM copies the bottom row up and leaves its own alone - which
12500 REM replicates whatever was on it down the whole exposed band. The
12510 REM flush cleaning that up is precisely its job. It is why this
12520 REM figure jumped from 0 to 610 the moment the visual prompts
12530 REM started being written on the bottom row, and that was the
12540 REM renderer behaving correctly, not a regression.
12550 DEF PROChwscroll
12560 LOCAL n%,t4
12570 T=TIME
12580 FOR n%=1 TO 10:PROCv_scroll(0,rows%-1,1,7,0):NEXT
12590 t4=TIME-T
12600 PROCw("scroll10_cs="+STR$(t4))
12610 PROCw("scroll10_above="+STR$(FNv_damage(0,rows%-11)))
12620 PROCw("scroll10_exposed="+STR$(FNv_damage(rows%-10,rows%-1)))
12630 n%=FNv_flush
12640 PROCw("scroll10_repainted="+STR$(n%))
12650 PROCv_text(2,rows%-2,"ten scrolls in "+STR$(t4)+" cs - SPACE to end",7,0,0)
12660 n%=FNv_flush
12670 ENDPROC
12680 :
12690 REM A question asked THROUGH THE ENGINE, on the bottom row, with
12700 REM the answer written to the results file so a visual check
12710 REM survives the session that made it.
12720 REM
12730 REM Not with PRINT. Output is routed to the Pi framebuffer, so a
12740 REM PRINT lands on cells the model believes are blank - and the
12750 REM shadow then agrees they need no painting, so the text would sit
12760 REM there through the following page and the flush would never take
12770 REM it away. Anything that appears on this screen has to arrive
12780 REM through the model, or it cannot be removed.
12790 REM A wrong key used to do NOTHING, which on a machine whose only output
12800 REM is the question itself is indistinguishable from a hang - the first
12810 REM hardware run of FBRUN stopped dead at the first question for exactly
12820 REM that reason. Every key now gets an answer, and the prompt says what
12830 REM it is waiting for.
12840 DEF PROCv_ask(k$,p$,v$)
12850 LOCAL k%,c$,n%,m$
12860 IF sim% THEN ENDPROC
12870 m$=""
12880 REPEAT
12890   PROCv_text(0,rows%-1,STRING$(cols%," "),7,0,0)
12900   PROCv_text(0,rows%-1,p$+m$,15,0,0)
12910   n%=FNv_flush
12920   k%=GET
12930   IF k%>96 AND k%<123 THEN k%=k%-32
12940   c$=CHR$(k%)
12950   m$="   <- press "+LEFT$(v$,1)
12960   FOR n%=2 TO LEN(v$):m$=m$+" or "+MID$(v$,n%,1):NEXT
12970 UNTIL INSTR(v$,c$)>0
12980 PROCw(k$+"="+c$)
12990 ENDPROC
13000 :
13010 DEF PROCwait
13020 LOCAL k%
13030 IF sim% THEN ENDPROC
13040 k%=GET
13050 ENDPROC
13060 :
13070 REM ================ results and errors ================
13080 DEF PROCopen
13090 rf%=OPENOUT(rf$)
13100 ENDPROC
13110 :
13120 DEF PROCw(s$)
13130 LOCAL i%
13140 IF rf%=0 THEN ENDPROC
13150 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
13160 BPUT#rf%,13:BPUT#rf%,10
13170 ENDPROC
13180 :
13190 DEF PROCshut
13200 IF rf%<>0 THEN CLOSE#rf%
13210 rf%=0
13220 ENDPROC
13230 :
13240 DEF PROCstop(s$)
13250 PROCw("fail="+s$)
13260 PROCshut
13270 VDU 23,1,1
13280 VDU 26:CLS
13290 PRINT "FBVDU cannot start: ";s$
13300 END
13310 :
13320 DEF PROCerr
13330 VDU 26,23,1,1
13340 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
13350 PROCshut
13360 CLS
13370 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
13380 REPORT:PRINT
13390 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is vdu% right for this core?"
13400 IF stage%=3 THEN PRINT "DIM failed - needs ";256*ch%+cols%*rows%*8;" bytes, plus ";sz%;" simulated screen."
13410 ENDPROC
13420 :