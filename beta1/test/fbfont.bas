   10 REM > FBFONT - harvest the driver's font out of the framebuffer
   20 REM
   30 REM FBVDU blits its own glyphs (docs/fbvdu.md), so it needs a font.
   40 REM Rather than transport one - DATA statements, or a binary with a
   50 REM load address supplied by hand, since LANMANFS keeps none (2.5)
   60 REM - take the one already on the screen: print a character through
   70 REM the driver, then read the pixels back out of the framebuffer.
   80 REM
   90 REM The font then matches the mode by construction, there is
  100 REM nothing to keep in step, and glyphs no BBC font carries can be
  110 REM defined with VDU 23 first and harvested the same way. 5.5d
  120 REM proved VDU 23 redefinition works on this driver, so the box
  130 REM pieces Claude Code draws with come through the same path.
  140 REM
  150 REM The whole harvested font is written to RESFONT on the share as
  160 REM hex, one line per glyph, so it can be rendered and checked off
  170 REM the machine - 256 glyphs is more than anyone will read off a
  180 REM monitor - and so that a font that harvests correctly can be
  190 REM kept and reused rather than re-harvested.
  200 REM
  210 REM It also settles the one thing the blitter cannot assume: within
  220 REM a word of four pixel bytes, is the LEFTMOST pixel the LOW byte?
  230 REM ARM is little-endian and the answer should be yes, but the
  240 REM re-blit at the end is what decides it - mirrored glyphs mean no.
  250 REM
  260 REM ARM NATIVE ONLY - copro 15, *ARMBASIC, *PIVDU 2.
  270 :
  280 md%=21:cw%=8:ch%=8
  290 lo%=32:hi%=126
  300 t$="Wg0 |-+ "
  310 rf$="RESFONT"
  320 :
  330 fb%=0:sz%=0:pit%=0:bg%=0:stage%=0:rf%=0
  340 ON ERROR PROCerr:END
  350 REM The results file is opened FIRST, before the DIM and before
  360 REM the mode change, so that a failure in either is recorded in it
  370 REM rather than only on a screen nobody kept.
  380 PROCopen
  390 PROCw("[fbfont]")
  400 REM A nonce, so two runs are never mistaken for each other and a
  410 REM file left behind by an earlier run cannot be read as this one.
  420 REM TIME is centiseconds since the machine came up, which differs
  430 REM between runs and needs no clock.
  440 PROCw("run="+STR$(TIME))
  450 REM DIM comes after ON ERROR, not before it: a DIM that will not
  460 REM fit is then our own error with a stage number rather than a
  470 REM bare BASIC message from a program that has not started (9.4).
  480 DIM q% 63,r% 63,font% 256*8,xp% 63
  490 :
  500 MODE md%
  510 REM Hide the cursor before harvesting. It sits one cell to the
  520 REM right of the character being read, but a driver that draws
  530 REM it anywhere else would be harvested as part of the glyph.
  540 VDU 23,1,0
  550 PROCvars
  560 IF fb%=0 THEN PROCw("fail=no framebuffer address"):PROCshut:END
  570 :
  580 stage%=1
  590 PROCbox
  600 T=TIME
  610 PROCharvest
  620 E=TIME-T
  630 PRINT
  640 PRINT hi%-lo%+1;" glyphs plus 6 box pieces in ";E;" cs, background ";bg%
  650 PRINT
  660 PROCw("glyphs="+STR$(hi%-lo%+1))
  670 PROCw("harvest_cs="+STR$(E))
  680 PROCw("background="+STR$(bg%))
  690 PROCw("blank="+STR$(FNblank))
  700 PROCdumpfont
  710 stage%=2
  720 PROCart(65)
  730 PROCpause
  740 stage%=3
  750 PROCart(224)
  760 PROCpause
  770 stage%=4
  780 PROCshow
  790 PRINT
  800 VDU 23,1,1
  810 PROCask("shapes","Do the two rows match, unmirrored?","YN")
  820 PROCw("[end]")
  830 PROCshut
  840 PRINT "FBFONT done - ";rf$;" is on the share for analysis."
  850 END
  860 :
  870 REM ---- ask the driver where the screen is -----------------------
  880 DEF PROCvars
  890 !q%=148:q%!4=150:q%!8=6:q%!12=-1
  900 SYS "OS_ReadVduVariables",q%,r%
  910 fb%=!r%:sz%=r%!4:pit%=r%!8
  920 PRINT "screen &";~fb%;"  ";sz%;" bytes  pitch ";pit%
  930 ENDPROC
  940 :
  950 REM ---- the six box pieces, from vdutest ------------------------
  960 REM The font has no box-drawing glyphs, so they are synthesised.
  970 REM Harvesting one of these proves a redefined character survives
  980 REM the round trip and lands in our table like any other.
  990 DEF PROCbox
 1000 VDU 23,224,0,0,0,&1F,&18,&18,&18,&18
 1010 VDU 23,225,0,0,0,&F8,&18,&18,&18,&18
 1020 VDU 23,226,&18,&18,&18,&1F,0,0,0,0
 1030 VDU 23,227,&18,&18,&18,&F8,0,0,0,0
 1040 VDU 23,228,0,0,0,&FF,0,0,0,0
 1050 VDU 23,229,&18,&18,&18,&18,&18,&18,&18,&18
 1060 ENDPROC
 1070 :
 1080 REM ---- the harvest ----------------------------------------------
 1090 REM One cell is used over and over: print into it, read it out.
 1100 REM The background index is read from a cell known to be blank
 1110 REM rather than assumed to be 0, so a driver that clears to
 1120 REM something else does not turn every glyph solid.
 1130 DEF PROCharvest
 1140 LOCAL c%
 1150 VDU 17,15,17,128
 1160 CLS
 1170 bg%=fb%?0
 1180 FOR c%=lo% TO hi%:PROCgrab(c%):NEXT
 1190 FOR c%=224 TO 229:PROCgrab(c%):NEXT
 1200 ENDPROC
 1210 :
 1220 REM Bit 7 is the leftmost pixel - the order a font file uses, and
 1230 REM the order the blitter's nibble table expects.
 1240 DEF PROCgrab(c%)
 1250 LOCAL y%,i%,a%,b%,m%
 1260 VDU 31,2,2,c%
 1270 FOR y%=0 TO ch%-1
 1280   a%=fb%+(2*ch%+y%)*pit%+2*cw%
 1290   b%=0:m%=128
 1300   FOR i%=0 TO cw%-1
 1310     IF a%?i%<>bg% THEN b%=b%+m%
 1320     m%=m% DIV 2
 1330   NEXT
 1340   font%?(c%*ch%+y%)=b%
 1350 NEXT
 1360 ENDPROC
 1370 :
 1380 REM ---- read it back as shapes -----------------------------------
 1390 DEF PROCart(c%)
 1400 LOCAL y%,i%,b%,s$
 1410 CLS
 1420 PRINT "glyph ";c%;" (";CHR$(c%);") as harvested:"
 1430 PRINT
 1440 FOR y%=0 TO ch%-1
 1450   b%=font%?(c%*ch%+y%)
 1460   s$=""
 1470   FOR i%=0 TO cw%-1
 1480     IF (b% AND 128)<>0 THEN s$=s$+"#" ELSE s$=s$+"."
 1490     b%=(b%*2) AND 255
 1500   NEXT
 1510   PRINT "   ";s$
 1520 NEXT
 1530 PRINT
 1540 PRINT "A recognisable shape means the read-back works. All dots"
 1550 PRINT "means the driver draws somewhere we cannot see, and the"
 1560 PRINT "font must be transported instead (docs/fbvdu.md, risks)."
 1570 ENDPROC
 1580 :
 1590 REM ---- blit it ourselves ----------------------------------------
 1600 REM The driver prints the string, then we print the same string
 1610 REM underneath it out of the harvested font, in a different colour
 1620 REM so there is no doubt which is which. This is the whole
 1630 REM renderer in miniature: PROCxp once, PROCblit per cell.
 1640 DEF PROCshow
 1650 LOCAL i%,c%
 1660 CLS
 1670 VDU 31,4,4
 1680 PRINT "driver: ";t$;CHR$228;CHR$229
 1690 PROCxp(2,0)
 1700 FOR i%=1 TO LEN(t$)
 1710   PROCblit(12+i%-1,6,ASC(MID$(t$,i%,1)))
 1720 NEXT
 1730 PROCblit(12+LEN(t$),6,228)
 1740 PROCblit(13+LEN(t$),6,229)
 1750 VDU 31,4,6
 1760 PRINT "ours:"
 1770 VDU 31,0,9
 1780 PRINT "Same shapes, one row apart and in green = the harvest is"
 1790 PRINT "good and the byte order is right."
 1800 PRINT "Mirrored = the leftmost pixel is the HIGH byte of the word,"
 1810 PRINT "and PROCxp must fill the four bytes the other way round."
 1820 ENDPROC
 1830 :
 1840 REM ---- the blitter ----------------------------------------------
 1850 REM xp% holds one word per nibble: the four pixel bytes that nibble
 1860 REM expands to for the current foreground and background. A glyph
 1870 REM row is then two lookups and two word stores, and a colour
 1880 REM change costs 16 word writes rather than anything per cell.
 1890 DEF PROCxp(f%,b%)
 1900 LOCAL n%,i%,m%,a%
 1910 FOR n%=0 TO 15
 1920   a%=xp%+n%*4:m%=8
 1930   FOR i%=0 TO 3
 1940     IF (n% AND m%)<>0 THEN a%?i%=f% ELSE a%?i%=b%
 1950     m%=m% DIV 2
 1960   NEXT
 1970 NEXT
 1980 ENDPROC
 1990 :
 2000 DEF PROCblit(x%,y%,g%)
 2010 LOCAL a%,f%,i%,b%
 2020 a%=fb%+y%*ch%*pit%+x%*cw%
 2030 f%=font%+g%*ch%
 2040 FOR i%=0 TO ch%-1
 2050   b%=f%?i%
 2060   !a%=xp%!((b% DIV 16)*4)
 2070   a%!4=xp%!((b% AND 15)*4)
 2080   a%=a%+pit%
 2090 NEXT
 2100 ENDPROC
 2110 :
 2120 REM ---- results file ---------------------------------------------
 2130 REM One byte at a time rather than BPUT#f,A$: the string form is
 2140 REM BASIC V, and this is the model the 6502 probes would copy.
 2150 DEF PROCopen
 2160 rf%=OPENOUT(rf$)
 2170 IF rf%=0 THEN PRINT "cannot open ";rf$;" - results to screen only"
 2180 ENDPROC
 2190 :
 2200 DEF PROCw(s$)
 2210 LOCAL i%
 2220 IF rf%=0 THEN PRINT s$:ENDPROC
 2230 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 2240 BPUT#rf%,13:BPUT#rf%,10
 2250 ENDPROC
 2260 :
 2270 DEF PROCshut
 2280 IF rf%<>0 THEN CLOSE#rf%
 2290 rf%=0
 2300 ENDPROC
 2310 :
 2320 DEF PROCask(k$,p$,v$)
 2330 LOCAL k%,c$
 2340 REM Fold case on LETTERS only, and take only the offered keys.
 2350 REM AND &DF uppercases a-z but mangles digits, so a question
 2360 REM offering 1 or 0 could never accept them (2026-08-20).
 2370 PRINT p$;" ";
 2380 REPEAT
 2390   k%=GET
 2400   IF k%>96 AND k%<123 THEN k%=k%-32
 2410   c$=CHR$(k%)
 2420 UNTIL INSTR(v$,c$)>0
 2430 VDU k%
 2440 PRINT
 2450 PROCw(k$+"="+c$)
 2460 ENDPROC
 2470 :
 2480 REM ---- the font itself ------------------------------------------
 2490 REM Eight hex bytes per glyph, tagged with the code. This is the
 2500 REM actual product of the probe: 2K that can be rendered, checked
 2510 REM glyph by glyph, and kept as a font file if the harvest is good.
 2520 DEF PROCdumpfont
 2530 LOCAL c%
 2540 PROCw("[font]")
 2550 FOR c%=lo% TO hi%:PROCwg(c%):NEXT
 2560 FOR c%=224 TO 229:PROCwg(c%):NEXT
 2570 ENDPROC
 2580 :
 2590 DEF PROCwg(c%)
 2600 LOCAL i%,s$
 2610 s$=STR$(c%)+" "
 2620 FOR i%=0 TO ch%-1:s$=s$+FNhex(font%?(c%*ch%+i%)):NEXT
 2630 PROCw(s$)
 2640 ENDPROC
 2650 :
 2660 DEF FNhex(b%)
 2670 LOCAL h$
 2680 h$="0123456789ABCDEF"
 2690 =MID$(h$,b% DIV 16+1,1)+MID$(h$,(b% AND 15)+1,1)
 2700 :
 2710 REM A glyph of all zero bytes harvested from a printable character
 2720 REM means the read-back found nothing. Space is expected to be
 2730 REM blank; anything else is the failure this probe exists to catch.
 2740 DEF FNblank
 2750 LOCAL c%,i%,n%,e%
 2760 n%=0
 2770 FOR c%=33 TO hi%
 2780   e%=0
 2790   FOR i%=0 TO ch%-1:e%=e%+font%?(c%*ch%+i%):NEXT
 2800   IF e%=0 THEN n%=n%+1
 2810 NEXT
 2820 =n%
 2830 :
 2840 DEF PROCpause
 2850 LOCAL k%
 2860 PRINT
 2870 PRINT "SPACE to continue";
 2880 k%=GET
 2890 ENDPROC
 2900 :
 2910 DEF PROCerr
 2920 VDU 26,23,1,1
 2930 PRINT
 2940 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
 2950 REPORT:PRINT
 2960 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
 2970 PROCshut
 2980 PRINT "Partial results are in ";rf$;" on the share."
 2990 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is *PIVDU 2 set?"
 3000 PRINT "Error 24 or similar at a SYS means the SWI is absent."
 3010 ENDPROC
