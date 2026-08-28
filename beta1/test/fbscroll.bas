   10 REM > FBSCROLL - does a paint after a scroll actually reach the pixels?
   20 REM
   30 REM Hardware says every stale cell was painted by the flush - ops=1, no
   40 REM scroll code - so PROCv_cell was called, the shadow was updated, and
   50 REM the glass did not change. And it only begins once the screen starts
   60 REM scrolling.
   70 REM
   80 REM So: fill the screen, flush, scroll, fill the exposed row, flush, and
   90 REM then check the glass against a repaint from scratch. Anything that
  100 REM differs is a cell the flush believed it had painted.
  110 REM
  120 REM Deterministic and small - a few flushes rather than a capture - so
  130 REM it runs offline and can be iterated without the hardware.
  140 :
  150 cols%=80:rows%=64
  160 cw%=8:ch%=8
  170 REM HARDWARE. The fault is on the real framebuffer and has never been
  180 REM reproduced against a DIMmed one, so this paints real pixels. It
  190 REM also avoids needing PIFONT, which simulation loads and which is no
  200 REM longer on the share - error 214 at stage 4 was exactly that.
  210 md%=21:vdu%=1:pivdu%=2
  220 sim%=FALSE
  230 glass%=TRUE
  240 rf$="RESSCRL"
  250 rf%=0
  260 :
  270 ON ERROR PROCerr:END
  280 PROCopen
  290 PROCw("[fbscroll1]")
  300 PROCw("run="+STR$(TIME))
  310 PROCv_boot
  320 IF vfail$<>"" THEN PROCw("fail="+vfail$):PROCshut:END
  330 PROCw("screen=&"+STR$~fb%+" pitch="+STR$(pit%))
  340 DIM copy% rows%*ch%*pit%
  350 REM The cursor is ON, as it is in real use. Every replay that ever
  360 REM checked the glass ran with it off.
  370 cvis%=TRUE
  380 :
  390 REM Every cell a different character, so a cell painted from the wrong
  400 REM place is visible rather than accidentally right.
  410 PROCpattern(0)
  420 n%=FNv_flush
  430 PROCw("first_paint="+STR$(n%))
  440 PROCcheck("first_paint")
  450 :
  460 REM SHORT lines. The exposed row is blanked by PROCv_scroll and then
  470 REM only its left end is written, so the flush has to paint sixty
  480 REM BLANKS over the characters the glass still shows there. Every stale
  490 REM cell found on hardware has been a blank, and filling the row
  500 REM completely - which is what this test did at first - never paints one
  510 REM over anything.
  520 FOR r%=1 TO 8
  530   PROCv_scroll(0,rows%-1,1,7,0)
  540   PROCshort(rows%-1,r%)
  550   n%=FNv_flush
  560 NEXT
  570 PROCcheck("after_8_scrolls")
  580 :
  590 FOR r%=9 TO 40
  600   PROCv_scroll(0,rows%-1,1,7,0)
  610   PROCshort(rows%-1,r%)
  620   n%=FNv_flush
  630 NEXT
  640 PROCcheck("after_40_scrolls")
  650 PROCw("[end]")
  660 PROCshut
  670 VDU 23,1,1:VDU 26:CLS
  680 PRINT "FBSCROLL done - RESSCRL is on the share."
  690 END
  700 :
10000 DEF PROCpattern(s%)
10010 LOCAL y%
10020 FOR y%=0 TO rows%-1:PROCrow(y%,s%+y%):NEXT
10030 ENDPROC
10040 :
10050 REM A line of varying length, the way a shell writes them: the rest of
10060 REM the row stays blank and must be painted over what was there.
10070 DEF PROCshort(y%,s%)
10080 LOCAL x%,w%
10090 w%=8+(s% MOD 40)
10100 FOR x%=0 TO cols%-1
10110   IF x%<w% THEN PROCv_put(x%,y%,33+((x%+s%) MOD 90),7,0,0) ELSE PROCv_put(x%,y%,32,7,0,0)
10120 NEXT
10130 ENDPROC
10140 :
10150 DEF PROCrow(y%,s%)
10160 LOCAL x%
10170 FOR x%=0 TO cols%-1
10180   PROCv_put(x%,y%,33+((x%+s%) MOD 90),7,0,0)
10190 NEXT
10200 ENDPROC
10210 :
10220 REM Keep the glass, force a repaint of every cell, and see which pixels
10230 REM change. A cell that changes was one the flush thought was done.
10240 DEF PROCcheck(w$)
10250 LOCAL i%,n%,bad%,x%,y%,first$
10260 FOR i%=0 TO rows%*ch%*pit%-4 STEP 4:copy%!i%=fb%!i%:NEXT
10270 FOR i%=0 TO cols%*rows%-1:shd%!(i%*4)=NOT scr%!(i%*4):NEXT
10280 con%=FALSE
10290 n%=FNv_flush
10300 bad%=0:first$=""
10310 FOR y%=0 TO rows%-1
10320   FOR x%=0 TO cols%-1
10330     IF FNdiff(x%,y%) THEN bad%=bad%+1:IF LEN(first$)<40 THEN first$=first$+STR$(x%)+","+STR$(y%)+" "
10340   NEXT
10350 NEXT
10360 PROCw(w$+"_stale="+STR$(bad%)+" at "+first$)
10370 ENDPROC
10380 :
10390 DEF FNdiff(x%,y%)
10400 LOCAL l%,r%,q%
10410 FOR l%=0 TO ch%-1
10420   r%=fb%+(y%*ch%+l%)*pit%+x%*cw%
10430   q%=copy%+(y%*ch%+l%)*pit%+x%*cw%
10440   IF !r%<>!q% OR r%!4<>q%!4 THEN =TRUE
10450 NEXT
10460 =FALSE
10470 :
10480 DEF PROCopen
10490 rf%=OPENOUT(rf$)
10500 ENDPROC
10510 :
10520 DEF PROCw(s$)
10530 LOCAL i%
10540 IF rf%=0 THEN ENDPROC
10550 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
10560 BPUT#rf%,13:BPUT#rf%,10
10570 ENDPROC
10580 :
10590 DEF PROCshut
10600 IF rf%<>0 THEN CLOSE#rf%
10610 rf%=0
10620 ENDPROC
10630 :
10640 DEF PROCerr
10650 VDU 26,23,1,1
10660 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
10670 PROCw("[end]")
10680 PROCshut
10690 CLS
10700 PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
10710 REPORT:PRINT
10720 ENDPROC
