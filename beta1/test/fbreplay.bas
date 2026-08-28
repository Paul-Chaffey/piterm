   10 REM > FBREPLAY - replay a captured stream and dump the resulting screen
   20 REM
   30 REM   *EXEC FBVDU / *EXEC FBREPLAY / RUN, or CHAIN a tokenised build
   40 REM
   50 REM Phase 3. A stream captured off a real pty by tools/ptycap.py goes in
   60 REM through PROCv_write a byte at a time, exactly as it will arrive from
   70 REM the socket, and what the cell model ends up holding comes out as text.
   80 REM tools/vtdiff.py puts the SAME capture through pyte at the SAME
   90 REM geometry and diffs the two grids.
  100 REM
  110 REM That is the first time this project can check a screen against a
  120 REM reference rather than against a photograph of a monitor.
  130 REM
  140 REM 80x64, because that is what the Beeb runs. The plan said 80x24 to keep
  150 REM two buffers inside the Master's BASIC space; BEEB_TUBE=12 gives 64MB
  160 REM and that reduction is dead - and capturing at the wrong height would
  170 REM test the wrong wrapping and the wrong scrolling.
  180 REM
  190 REM Model only: no framebuffer, no font, no blitter. What is being checked
  200 REM is the parser and the cell model, and pixels would only make the run
  210 REM slower.
  220 :
  230 cols%=80:rows%=64
  240 cw%=8:ch%=8
  250 md%=21:vdu%=0:pivdu%=2
  260 sim%=TRUE
  270 glass%=FALSE
  280 cap$="CAP"
  290 out$="GRID"
  300 :
  310 DIM buf% cols%+1
  320 rf%=0
  330 ON ERROR PROCerr:END
  340 PROCv_boot
  350 IF vfail$<>"" THEN PRINT "cannot start: ";vfail$:END
  360 PROCreplay
  370 PROCdump
  380 PRINT "FBREPLAY done"
  390 END
  400 :
  410 REM The capture is loaded in ONE operation and then walked in memory.
  420 REM Read byte by byte with BGET# it took 3393 cs for 582 bytes - 58ms
  430 REM each, because every BGET# is a Tube round trip and a host filing
  440 REM system call. The bytes are identical either way; only the route
  450 REM they arrive by is different, and that is not what is under test.
10000 DEF PROCreplay
10010 LOCAL f%,i%,n%
10020 f%=OPENIN(cap$)
10030 IF f%=0 THEN PRINT "cannot open ";cap$:END
10040 n%=EXT#f%
10050 CLOSE#f%
10060 IF n%<1 THEN PRINT cap$;" is empty":END
10070 DIM cap% n%
10080 OSCLI("LOAD "+cap$+" "+STR$~cap%)
10090 T=TIME
10100 FOR i%=0 TO n%-1
10110   PROCv_write(cap%?i%)
10120 NEXT
10130 bytes%=n%
10140 cs%=TIME-T
10150 PRINT "replayed ";n%;" bytes in ";cs%;" cs"
10160 ENDPROC
10170 :
10180 REM The dump is three sections because three different things can be
10190 REM wrong and a single grid of characters hides two of them:
10200 REM
10210 REM   [grid]  what is on the screen, one line per row
10220 REM   [odd]   cells whose glyph is not printable ASCII - the DEC line
10230 REM           drawing set lives at 128-159 and would otherwise all look
10240 REM           like the same placeholder
10250 REM   [runs]  attribute runs, so a colour or a reverse-video bug shows up
10260 REM           even where the text is identical
10270 DEF PROCdump
10280 LOCAL x%,y%
10290 rf%=OPENOUT(out$)
10300 PROCw("[fbreplay1]")
10310 PROCw("geometry="+STR$(cols%)+"x"+STR$(rows%))
10320 PROCw("bytes="+STR$(bytes%)+" cs="+STR$(cs%))
10330 PROCw("cursor="+STR$(cx%)+","+STR$(cy%))
10340 PROCw("[grid]")
10350 FOR y%=0 TO rows%-1:PROCw(FNrow(y%)):NEXT
10360 PROCw("[odd]")
10370 FOR y%=0 TO rows%-1
10380   FOR x%=0 TO cols%-1
10390     IF FNg(x%,y%)<32 OR FNg(x%,y%)>126 THEN PROCw(STR$(y%)+" "+STR$(x%)+" "+STR$(FNg(x%,y%)))
10400   NEXT
10410 NEXT
10420 PROCw("[runs]")
10430 FOR y%=0 TO rows%-1:PROCruns(y%):NEXT
10440 PROCw("[end]")
10450 PROCshut
10460 ENDPROC
10470 :
10480 REM One line per run of identical attributes: row, first column, length,
10490 REM foreground, background, flags.
10500 DEF PROCruns(y%)
10510 LOCAL x%,s%,f%,b%,l%
10520 s%=0:f%=FNf(0,y%):b%=FNb(0,y%):l%=FNl(0,y%)
10530 FOR x%=1 TO cols%-1
10540   IF FNf(x%,y%)<>f% OR FNb(x%,y%)<>b% OR FNl(x%,y%)<>l% THEN PROCrun(y%,s%,x%-s%,f%,b%,l%):s%=x%:f%=FNf(x%,y%):b%=FNb(x%,y%):l%=FNl(x%,y%)
10550 NEXT
10560 PROCrun(y%,s%,cols%-s%,f%,b%,l%)
10570 ENDPROC
10580 :
10590 DEF PROCrun(y%,x%,n%,f%,b%,l%)
10600 PROCw(STR$(y%)+" "+STR$(x%)+" "+STR$(n%)+" "+STR$(f%)+" "+STR$(b%)+" "+STR$(l%))
10610 ENDPROC
10620 :
10630 REM Printable ASCII as itself, anything else as ~ - the [odd] section
10640 REM says what it really was.
10650 DEF FNrow(y%)
10660 LOCAL i%,c%
10670 FOR i%=0 TO cols%-1
10680   c%=FNg(i%,y%)
10690   IF c%<32 OR c%>126 THEN c%=126
10700   buf%?i%=c%
10710 NEXT
10720 buf%?cols%=13
10730 =$buf%
10740 :
10750 DEF FNg(x%,y%)
10760 =?(scr%+((y%*cols%+x%)*4))+(?(scr%+((y%*cols%+x%)*4)+1) AND 15)*256
10770 :
10780 DEF FNf(x%,y%)
10790 =?(scr%+((y%*cols%+x%)*4)+2)
10800 :
10810 DEF FNb(x%,y%)
10820 =?(scr%+((y%*cols%+x%)*4)+3)
10830 :
10840 DEF FNl(x%,y%)
10850 =?(scr%+((y%*cols%+x%)*4)+1) DIV 16
10860 :
10870 DEF PROCw(s$)
10880 LOCAL i%
10890 IF rf%=0 THEN ENDPROC
10900 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
10910 BPUT#rf%,13:BPUT#rf%,10
10920 ENDPROC
10930 :
10940 DEF PROCshut
10950 IF rf%<>0 THEN CLOSE#rf%
10960 rf%=0
10970 ENDPROC
10980 :
10990 DEF PROCerr
11000 PRINT:PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
11010 REPORT:PRINT
11020 PROCshut
11030 ENDPROC
