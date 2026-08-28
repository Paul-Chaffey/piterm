   10 REM > VDUTEST - Step 0c: can the Pi VDU driver carry a terminal?
   20 REM
   30 REM Answers specification.md 7, open questions 2 and 4:
   40 REM   VDU 31  cursor positioning      - a TUI repaints by seeking
   50 REM   VDU 17  colour                  - how many are actually reachable
   60 REM   VDU 23  character redefinition  - we need box-drawing glyphs
   70 REM   throughput                      - chars/sec, i.e. is a repaint viable
   80 REM
   90 REM Run on the co-processor with the Pi framebuffer live: vdu=1 in
  100 REM cmdline.txt, then *PIVDU 2 (native ARM) or CALL &300 (6502 co-pro).
  110 REM
  120 REM BASIC IV safe - no CASE, no WHILE, no REPORT$ (see 9.4).
  130 :
  140 md%=21
  150 :
  160 REM Everything the error handler can touch, initialised first.
  170 cols%=0:rows%=0:cur%=0:cps%=0:cpc%=0:E=0:T=0
  180 ON ERROR PROCerr:END
  190 :
  200 MODE md%
  210 PROCgeom
  220 PROCcursor
  230 PROCspeed
  240 PROCreport
  250 PROCpause
  260 PROCcolour
  270 PROCpause
  280 PROCredef
  290 PROCpause
  300 PROCbox
  310 PRINT
  320 PRINT "VDUTEST done - record results against specification.md 7"
  330 END
  340 :
  350 REM ---- silent probes ----------------------------------------------
  360 :
  370 REM Walk the cursor out along each axis. A VDU 31 past the edge is
  380 REM ignored, so the last position that sticks IS the edge.
  390 DEF PROCgeom
  400 LOCAL x%,y%
  410 CLS
  420 FOR x%=0 TO 199
  430   VDU 31,x%,0
  440   IF POS=x% THEN cols%=x%+1
  450 NEXT
  460 FOR y%=0 TO 199
  470   VDU 31,0,y%
  480   IF VPOS=y% THEN rows%=y%+1
  490 NEXT
  500 IF cols%=0 THEN cols%=80
  510 IF rows%=0 THEN rows%=32
  520 ENDPROC
  530 :
  540 REM Seek to eight scattered points and read back where we landed.
  550 DEF PROCcursor
  560 LOCAL i%,x%,y%
  570 cur%=TRUE
  580 FOR i%=1 TO 8
  590   x%=(i%*7) MOD cols%
  600   y%=(i%*5) MOD rows%
  610   VDU 31,x%,y%
  620   IF POS<>x% OR VPOS<>y% THEN cur%=FALSE
  630 NEXT
  640 ENDPROC
  650 :
  660 REM Plain text, then text with a colour change per line - a TUI does
  670 REM the latter constantly, and it is the more honest number.
  680 DEF PROCspeed
  690 LOCAL i%,n%,s$
  700 s$=STRING$(cols%-2,"#")
  710 n%=200*(cols%-1)
  720 CLS
  730 T=TIME
  740 FOR i%=1 TO 200
  750   PRINT s$
  760 NEXT
  770 E=TIME-T
  780 IF E>0 THEN cps%=(n%*100) DIV E
  790 CLS
  800 T=TIME
  810 FOR i%=1 TO 200
  820   VDU 17,(i% MOD 7)+1
  830   PRINT s$
  840 NEXT
  850 E=TIME-T
  860 IF E>0 THEN cpc%=(n%*100) DIV E
  870 VDU 17,7
  880 ENDPROC
  890 :
  900 REM ---- report ------------------------------------------------------
  910 :
  920 DEF PROCreport
  930 CLS
  940 PRINT "VDUTEST - mode ";md%
  950 PRINT STRING$(46,"-")
  960 PRINT "text geometry     ";cols%;" x ";rows%
  970 PRINT "VDU 31 cursor     ";
  980 IF cur% THEN PRINT "OK" ELSE PRINT "*** FAILED"
  990 PRINT "plain text        ";cps%;" chars/sec"
 1000 PRINT "with colour       ";cpc%;" chars/sec"
 1010 PRINT
 1020 IF cps%>0 THEN PRINT "full screen       ";(cols%*rows%*100) DIV cps%;" cs"
 1030 PRINT
 1040 PRINT "The network side sustains 3082 bytes/sec (5.5c), so if"
 1050 PRINT "the figures above are far above that, the display is not"
 1060 PRINT "the bottleneck and the terminal is viable as designed."
 1070 ENDPROC
 1080 :
 1090 REM ---- visual checks -----------------------------------------------
 1100 :
 1110 REM REVISED 2026-08-19 after palette2: this page originally swept
 1115 REM GCOL 0,n for n=0-255 and reported "256 distinct swatches = no
 1120 REM TINT needed", which was wrong twice over. A 256-colour mode is
 1125 REM 64 colours x 4 tints (2.3); GCOL above 63 washes out to white,
 1130 REM and the tint is a separate selector - VDU 23,17,r,t| with r=2
 1135 REM for graphics foreground, t = 0/64/128/192.
 1140 DEF PROCcolour
 1145 LOCAL c%,t%,x%,y%
 1150 CLS
 1155 PRINT "VDU 17 text colours 0-63:"
 1160 PRINT
 1165 FOR c%=0 TO 63
 1170   VDU 17,c%
 1175   PRINT "##";
 1180 NEXT
 1185 VDU 17,7
 1190 PRINT:PRINT
 1195 PRINT "GCOL 0,0-63 across, tint 0/64/128/192 down:"
 1200 FOR t%=0 TO 3
 1205   VDU 23,17,2,t%*64,0,0,0,0,0,0
 1210   y%=200+(3-t%)*90
 1215   FOR c%=0 TO 63
 1220     x%=c%*20
 1225     MOVE x%,y%
 1230     MOVE x%+18,y%
 1235     PLOT 85,x%,y%+85
 1240     PLOT 85,x%+18,y%+85
 1245   NEXT
 1250 NEXT
 1255 VDU 23,17,2,0,0,0,0,0,0,0
 1260 GCOL 0,7
 1265 VDU 31,0,rows%-2
 1270 PRINT "four bands, hue kept, lighter downwards = 256 usable shades";
 1275 ENDPROC
 1390 :
 1400 REM Claude Code draws its frame with box-drawing glyphs no BBC font
 1410 REM has. If VDU 23 works we can synthesise them - open question 7.
 1420 DEF PROCredef
 1430 CLS
 1440 VDU 23,224,0,0,0,&1F,&18,&18,&18,&18
 1450 VDU 23,225,0,0,0,&F8,&18,&18,&18,&18
 1460 VDU 23,226,&18,&18,&18,&1F,0,0,0,0
 1470 VDU 23,227,&18,&18,&18,&F8,0,0,0,0
 1480 VDU 23,228,0,0,0,&FF,0,0,0,0
 1490 VDU 23,229,&18,&18,&18,&18,&18,&18,&18,&18
 1500 PRINT "VDU 23 redefinition - six box-drawing pieces:"
 1510 PRINT
 1520 PRINT CHR$(224);CHR$(228);CHR$(225);" ";
 1530 PRINT CHR$(229);" ";
 1540 PRINT CHR$(226);CHR$(228);CHR$(227)
 1550 PRINT
 1560 PRINT "corners, horizontal, vertical. If those are garbage or"
 1570 PRINT "unchanged, VDU 23 is unsupported and the frame must be"
 1580 PRINT "drawn some other way."
 1590 ENDPROC
 1600 :
 1610 REM Put them together: the shape Claude Code actually draws.
 1620 DEF PROCbox
 1630 LOCAL i%,w%
 1640 CLS
 1650 w%=cols%-4
 1660 VDU 31,1,1
 1670 PRINT CHR$(224);
 1680 FOR i%=1 TO w%:PRINT CHR$(228);:NEXT
 1690 PRINT CHR$(225)
 1700 FOR i%=1 TO 3
 1710   VDU 31,1,1+i%
 1720   PRINT CHR$(229);
 1730   VDU 31,2+w%,1+i%
 1740   PRINT CHR$(229);
 1750 NEXT
 1760 VDU 31,1,5
 1770 PRINT CHR$(226);
 1780 FOR i%=1 TO w%:PRINT CHR$(228);:NEXT
 1790 PRINT CHR$(227)
 1800 VDU 31,3,3
 1810 VDU 17,3
 1820 PRINT "> claude code, on a BBC Master";
 1830 VDU 17,7
 1840 VDU 31,0,7
 1850 ENDPROC
 1860 :
 1870 DEF PROCpause
 1880 PRINT
 1890 PRINT "press SPACE";
 1900 i%=GET
 1910 ENDPROC
 1920 :
 1930 DEF PROCerr
 1940 VDU 17,7
 1950 PRINT
 1960 PRINT "Error ";ERR;" at line ";ERL
 1970 REPORT:PRINT
 1980 IF ERR=25 THEN PRINT "MODE ";md%;" refused - try MODE 64 (640x512 8bpp)"
 1990 ENDPROC
