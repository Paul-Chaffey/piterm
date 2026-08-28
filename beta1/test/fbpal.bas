   10 REM > FBPAL - how deep is the palette when we own the bytes?
   20 REM
   30 REM 2.3 measured MODE 21 THROUGH the VDU driver and found 64
   40 REM colours x 4 tints, with VDU 19 reprogramming the 16 low
   50 REM palette entries. 2.3a then established that the framebuffer
   60 REM address is exposed, and fbtest confirmed on hardware that a
   70 REM poked byte becomes a pixel.
   80 REM
   90 REM In 8bpp every byte IS a palette index, so the question is no
  100 REM longer what GCOL can reach - it is how many of the 256 entries
  110 REM can be PROGRAMMED. If the answer is all of them, then
  120 REM xterm-256color is exact for FBVDU and the nearest-colour table
  130 REM 2.3 asks for is never written. If it is 16, FNx256 stands.
  140 REM
  150 REM Results are written to RESPAL on the share, so the answer is a
  160 REM file to read rather than a screen to describe.
  170 REM
  180 REM RUN 2026-08-20 established that the machine cannot answer this
  190 REM for itself: OS_ReadPalette returns without error and writes
  200 REM NOTHING - 1024 reads across four dumps, every one zero, taken
  210 REM after the palette had just been reprogrammed. It is a stub, and
  220 REM not erroring is not the same as being implemented. PROCtrypal
  230 REM now checks the values rather than trusting the call.
  240 REM
  250 REM So the eye is the instrument, and the job of this probe is to
  260 REM ask a question the eye cannot get wrong. Counting bands in a
  270 REM 16-row grid is exactly such a question, so the decisive test is
  280 REM now four labelled blocks and one keypress.
  290 REM
  300 REM 2.3 warns that POINT reports the colour and never the tint, so
  310 REM it cannot measure any of this. Do not reach for it again.
  320 REM
  330 REM ARM NATIVE ONLY - copro 15, reached with *ARMBASIC, output
  340 REM routed with *PIVDU 2 BEFORE the mode is set.
  350 :
  360 md%=21
  370 rf$="RESPAL"
  380 :
  390 fb%=0:sz%=0:pit%=0:stage%=0:rf%=0:palok%=FALSE
  400 ON ERROR PROCerr:END
  410 REM The results file is opened FIRST, before the DIM and before
  420 REM the mode change, so that a failure in either is recorded in it
  430 REM rather than only on a screen nobody kept.
  440 PROCopen
  450 PROCw("[fbpal]")
  460 REM A nonce, so two runs are never mistaken for each other and a
  470 REM file left behind by an earlier run cannot be read as this one.
  480 REM TIME is centiseconds since the machine came up, which differs
  490 REM between runs and needs no clock.
  500 PROCw("run="+STR$(TIME))
  510 REM DIM comes after ON ERROR, not before it: a DIM that will not
  520 REM fit is then our own error with a stage number rather than a
  530 REM bare BASIC message from a program that has not started (9.4).
  540 DIM q% 63,r% 63
  550 :
  560 MODE md%
  570 REM The cursor blinks wherever the driver last left it, which
  580 REM here is on top of a swatch. Hide it - and if the driver
  590 REM ignores VDU 23,1 nothing is lost by asking.
  600 VDU 23,1,0
  610 PROCvars
  620 IF fb%=0 THEN PROCw("fail=no framebuffer address"):PROCshut:END
  630 :
  640 REM ---- 1: can the machine read the palette back itself? ---------
  650 stage%=1
  660 PROCtrypal
  670 IF palok% THEN PROCdump("before")
  680 :
  690 REM ---- 2: the decisive one - four blocks, one keypress ----------
  700 REM Two blocks drawn in entries 200 and 100, two more in 8 and 4,
  710 REM which are what 200 and 100 become if VDU 19 wraps mod 16. Then
  720 REM 200 and 100 are reprogrammed. Whichever pair changes says which
  730 REM world we are in, and no one has to count rows to report it.
  740 stage%=2
  750 PROCblocks
  760 PROCsay("1 of 5: watch these four blocks")
  770 PRINT "A is entries 200 and 100. B is entries 8 and 4, which are"
  780 PRINT "what 200 and 100 become if VDU 19 wraps mod 16."
  790 PROCpause
  800 VDU 19,200,16,255,0,0
  810 VDU 19,100,16,0,255,0
  820 PROCsay("200 asked for red, 100 asked for green")
  830 PRINT "  A - the blocks marked A changed"
  840 PRINT "  B - the blocks marked B changed instead"
  850 PRINT "  N - nothing changed"
  860 PROCask("blocks","Which pair changed - A, B or N?","ABN")
  870 PROCpause
  880 :
  890 REM ---- 3: the 256 entries as the driver leaves them --------------
  900 stage%=3
  910 PROCgrid
  920 PROCsay("2 of 5: the 256 palette entries as they come")
  930 PRINT "Every patch is one poked byte value, 0-255, left to right"
  940 PRINT "and top to bottom."
  950 IF palok% THEN PRINT "RGB recorded to the file." ELSE PROCask("distinct256","Are all 256 patches distinct?","YN")
  960 PROCpause
  970 :
  980 REM ---- 3: can anything above entry 15 be reprogrammed? ----------
  990 REM VDU 19 changes are retroactive on what is already displayed
 1000 REM (2.3), so the grid answers this without being redrawn. Asking
 1010 REM for entries 16-31 specifically is what separates the three
 1020 REM outcomes - a mod-16 wrap would recolour row 0, not row 1.
 1030 stage%=4
 1040 FOR l%=16 TO 31:VDU 19,l%,16,0,0,255:NEXT
 1050 PROCsay("3 of 5: entries 16-31 asked to become pure blue")
 1060 IF palok% THEN PROCdump("after1631")
 1070 PRINT "  ROW 1 turned blue - entries above 15 ARE programmable"
 1080 PRINT "  ROW 0 turned blue - VDU 19 wrapped mod 16; only 16 exist"
 1090 PRINT "  nothing changed   - VDU 19 is ignored above 15"
 1100 REM Bands are numbered on the grid itself now. Counting them was
 1110 REM what turned a clear result into an ambiguous one on 2026-08-20.
 1120 PROCask("blue","Which numbered band turned blue - 1, 0 or N?","10N")
 1130 PROCpause
 1140 :
 1150 REM ---- 4: the whole xterm-256 palette, if it will take it -------
 1160 stage%=5
 1170 PROCxterm
 1180 PROCsay("4 of 5: all 256 defined as the xterm-256 palette")
 1190 IF palok% THEN PROCdump("afterxterm")
 1200 PRINT "If this is now an xterm colour chart - the ANSI 16, then a"
 1210 PRINT "6x6x6 cube, then a grey ramp - FBVDU can be exact and the"
 1220 PRINT "nearest-colour reduction in FNx256 is never needed."
 1230 PROCask("xterm","Does it look like an xterm chart?","YN")
 1240 PROCpause
 1250 :
 1260 REM ---- 5: the other route, if VDU 19 refused --------------------
 1270 stage%=6
 1280 PROCosword
 1290 :
 1300 VDU 23,1,1
 1310 PROCw("[end]")
 1320 PROCshut
 1330 PRINT "FBPAL done - ";rf$;" is on the share for analysis."
 1340 END
 1350 :
 1360 REM ---- results file ---------------------------------------------
 1370 REM BPUT one byte at a time rather than BPUT#f,A$ - the string form
 1380 REM is BASIC V and this file is meant to stay readable as a model
 1390 REM for the 6502 probes. CR LF so the Linux side can read it
 1400 REM without translating anything.
 1410 DEF PROCopen
 1420 rf%=OPENOUT(rf$)
 1430 IF rf%=0 THEN PRINT "cannot open ";rf$;" - results to screen only"
 1440 ENDPROC
 1450 :
 1460 DEF PROCw(s$)
 1470 LOCAL i%
 1480 IF rf%=0 THEN PRINT s$:ENDPROC
 1490 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1500 BPUT#rf%,13:BPUT#rf%,10
 1510 ENDPROC
 1520 :
 1530 DEF PROCshut
 1540 IF rf%<>0 THEN CLOSE#rf%
 1550 rf%=0
 1560 ENDPROC
 1570 :
 1580 REM A question whose ANSWER goes in the file. The eye is still the
 1590 REM instrument where the machine has none, but the reading is
 1600 REM recorded rather than remembered.
 1610 REM Only the offered keys are taken. A run on 2026-08-20 recorded
 1620 REM blue=? because anything under 32 was accepted and written as a
 1630 REM question mark, which is how the one question that mattered came
 1640 REM back unanswered.
 1650 DEF PROCask(k$,p$,v$)
 1660 LOCAL k%,c$
 1670 PRINT p$;" ";
 1680 REM Fold case on LETTERS only. AND &DF uppercases a-z but mangles
 1690 REM digits - "1" is &31 and &31 AND &DF is &11 - so a question
 1700 REM offering 1, 0 or N could never accept 1 or 0. Found at the
 1710 REM machine 2026-08-20.
 1720 REPEAT
 1730   k%=GET
 1740   IF k%>96 AND k%<123 THEN k%=k%-32
 1750   c$=CHR$(k%)
 1760 UNTIL INSTR(v$,c$)>0
 1770 VDU k%
 1780 PRINT
 1790 PROCw(k$+"="+c$)
 1800 ENDPROC
 1810 :
 1820 REM ---- ask the driver where the screen is -----------------------
 1830 REM 148 SCREENSTART, 150 TOTALSCREENSIZE, 6 line length in bytes.
 1840 DEF PROCvars
 1850 !q%=148:q%!4=150:q%!8=6:q%!12=-1
 1860 SYS "OS_ReadVduVariables",q%,r%
 1870 fb%=!r%:sz%=r%!4:pit%=r%!8
 1880 PRINT "screen &";~fb%;"  ";sz%;" bytes  pitch ";pit%
 1890 PROCw("mode="+STR$(md%))
 1900 PROCw("screen=&"+STR$~fb%)
 1910 PROCw("size="+STR$(sz%))
 1920 PROCw("pitch="+STR$(pit%))
 1930 ENDPROC
 1940 :
 1950 REM ---- reading the palette back ---------------------------------
 1960 REM OS_ReadPalette on RISC OS: R0 colour, R1 type 16, returning the
 1970 REM two flash colours as &BBGGRR00 words. If PiTubeDirect
 1980 REM implements it the whole question becomes data. ON ERROR LOCAL
 1990 REM so its absence is recorded rather than fatal.
 2000 DEF PROCtrypal
 2010 LOCAL n%,a%,b%,f%
 2020 palok%=TRUE
 2030 ON ERROR LOCAL palok%=FALSE:PROCw("readpalette=absent"):ENDPROC
 2040 SYS "OS_ReadPalette",0,16 TO ,,f%,b%
 2050 REM A stub returns success and writes nothing, so every entry reads
 2060 REM alike. Sixteen entries that are all the same value is not a
 2070 REM palette, it is an unimplemented SWI answering politely.
 2080 FOR n%=1 TO 15
 2090   SYS "OS_ReadPalette",n%,16 TO ,,a%,b%
 2100   IF a%<>f% THEN PROCw("readpalette=present"):ENDPROC
 2110 NEXT
 2120 palok%=FALSE
 2130 PROCw("readpalette=stub")
 2140 ENDPROC
 2150 :
 2160 REM Every entry as a hex word, tagged with which stage it was read
 2170 REM at, so the Linux side can diff before against after and answer
 2180 REM the programmable question without anyone looking at a screen.
 2190 DEF PROCdump(w$)
 2200 LOCAL n%,a%,b%,s$
 2210 PROCw("[palette "+w$+"]")
 2220 FOR n%=0 TO 255
 2230   SYS "OS_ReadPalette",n%,16 TO ,,a%,b%
 2240   s$=STR$(n%)+" &"+STR$~a%
 2250   IF b%<>a% THEN s$=s$+" &"+STR$~b%
 2260   PROCw(s$)
 2270 NEXT
 2280 ENDPROC
 2290 :
 2300 REM ---- the grid -------------------------------------------------
 2310 REM 16 x 16 patches of 40 x 27 pixels, poked a word at a time.
 2320 REM The word is built in memory rather than by arithmetic: byte
 2330 REM values above 127 shifted into the top of a word overflow
 2340 REM BASIC's signed integer and raise Number too big.
 2350 DEF PROCgrid
 2360 LOCAL c%,x%,y%,row%,i%,a%,w%
 2370 CLS
 2380 FOR c%=0 TO 255
 2390   x%=(c% AND 15)*40:y%=(c% DIV 16)*27
 2400   q%?0=c%:q%?1=c%:q%?2=c%:q%?3=c%:w%=!q%
 2410   FOR row%=0 TO 25
 2420     a%=fb%+(y%+row%)*pit%+x%
 2430     FOR i%=0 TO 36 STEP 4:a%!i%=w%:NEXT
 2440   NEXT
 2450 NEXT
 2460 PROCnumber
 2470 ENDPROC
 2480 :
 2490 REM Number the bands on the grid itself. Asking someone to count
 2500 REM sixteen 27-pixel bands and report which one changed is how a
 2510 REM clear result came back ambiguous on 2026-08-20.
 2520 DEF PROCnumber
 2530 LOCAL n%
 2540 FOR n%=0 TO 15
 2550   VDU 31,0,n%*27 DIV 8
 2560   PRINT ;n%;
 2570 NEXT
 2580 ENDPROC
 2590 :
 2600 REM ---- the four blocks ------------------------------------------
 2610 REM 120 x 56 pixels each, labelled underneath by the driver's own
 2620 REM text so the label cannot be mistaken for part of the answer.
 2630 DEF PROCblocks
 2640 CLS
 2650 PROCfill(0,200):PROCfill(1,8):PROCfill(2,100):PROCfill(3,4)
 2660 VDU 31,0,8
 2670 PRINT "  A 200        B 8          A 100        B 4"
 2680 ENDPROC
 2690 :
 2700 DEF PROCfill(k%,c%)
 2710 LOCAL x%,row%,i%,a%,w%
 2720 x%=k%*160
 2730 q%?0=c%:q%?1=c%:q%?2=c%:q%?3=c%:w%=!q%
 2740 FOR row%=0 TO 55
 2750   a%=fb%+row%*pit%+x%
 2760   FOR i%=0 TO 116 STEP 4:a%!i%=w%:NEXT
 2770 NEXT
 2780 ENDPROC
 2790 :
 2800 REM ---- the xterm-256 palette ------------------------------------
 2810 REM 0-15 the ANSI 16, exactly as PROCpal defines them in beebterm.
 2820 REM 16-231 a 6x6x6 cube on 0,95,135,175,215,255. 232-255 grey.
 2830 DEF PROCxterm
 2840 LOCAL n%,i%,rd%,gr%,bl%
 2850 RESTORE
 2860 FOR n%=0 TO 15:READ rd%,gr%,bl%:VDU 19,n%,16,rd%,gr%,bl%:NEXT
 2870 FOR n%=16 TO 231
 2880   i%=n%-16
 2890   rd%=FNcube(i% DIV 36):gr%=FNcube((i% DIV 6) MOD 6):bl%=FNcube(i% MOD 6)
 2900   VDU 19,n%,16,rd%,gr%,bl%
 2910 NEXT
 2920 FOR n%=232 TO 255
 2930   gr%=8+(n%-232)*10
 2940   VDU 19,n%,16,gr%,gr%,gr%
 2950 NEXT
 2960 ENDPROC
 2970 :
 2980 DEF FNcube(v%)
 2990 IF v%=0 THEN =0
 3000 =55+40*v%
 3010 :
 3020 DATA 0,0,0, 170,0,0, 0,170,0, 170,85,0
 3030 DATA 0,0,170, 170,0,170, 0,170,170, 170,170,170
 3040 DATA 85,85,85, 255,85,85, 85,255,85, 255,255,85
 3050 DATA 85,85,255, 255,85,255, 85,255,255, 255,255,255
 3060 :
 3070 REM ---- the other route ------------------------------------------
 3080 REM OS_Word 12 is RISC OS's palette call: logical colour, then 16
 3090 REM to mean the r,g,b that follow. Worth a try only if VDU 19 was
 3100 REM the thing refusing. ON ERROR LOCAL again - an unimplemented
 3110 REM SWI must not cost the results file.
 3120 DEF PROCosword
 3130 LOCAL k%
 3140 PRINT "5 of 5: trying OS_Word 12 as well"
 3150 ON ERROR LOCAL PROCw("osword12=absent"):ENDPROC
 3160 q%?0=200:q%?1=16:q%?2=255:q%?3=0:q%?4=0
 3170 SYS "OS_Word",12,q%
 3180 PROCw("osword12=accepted")
 3190 PRINT "entry 200 asked for red - band 12, column 8, and the A"
 3200 PRINT "blocks above were drawn in 200 as well."
 3210 IF palok% THEN PROCdump("afterosword")
 3220 PROCask("osword","Did anything drawn in 200 turn red?","YN")
 3230 ENDPROC
 3240 :
 3250 REM ---- screen furniture -----------------------------------------
 3260 REM The grid occupies rows 0-53. Text lives below it, and never
 3270 REM touches column 79: the Pi driver ignores VDU 23,16 (9.3), so a
 3280 REM character in the last column would scroll the whole screen.
 3290 DEF PROCsay(s$)
 3300 LOCAL i%
 3310 FOR i%=55 TO 63:VDU 31,0,i%:PRINT SPC(79);:NEXT
 3320 VDU 31,0,55
 3330 PRINT s$
 3340 ENDPROC
 3350 :
 3360 DEF PROCpause
 3370 LOCAL k%
 3380 VDU 31,0,63
 3390 PRINT "SPACE to continue";
 3400 k%=GET
 3410 ENDPROC
 3420 :
 3430 DEF PROCerr
 3440 VDU 26,23,1,1
 3450 PRINT
 3460 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
 3470 REPORT:PRINT
 3480 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
 3490 PROCshut
 3500 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is *PIVDU 2 set?"
 3510 PRINT "Partial results are in ";rf$;" on the share."
 3520 ENDPROC
