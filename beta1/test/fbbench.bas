   10 REM > FBBENCH - can BASIC carry the blitter, and at which cell size?
   20 REM
   30 REM 2.3a's arithmetic says a full 80x64 screen of 8x8 cells is well
   40 REM under a second from BASIC, and 5.5d measured the display at 20x
   50 REM the network. FBVDU decouples the model from the renderer - a
   60 REM whole drain's worth of bytes is applied to the cell model, then
   70 REM ONE flush - so a few repaints a second is enough. That argument
   80 REM is arithmetic. This turns it into numbers.
   90 REM
  100 REM It measures what the engine actually does, not VDU throughput:
  110 REM the nibble-table cell blit three ways, the shadow compare that
  120 REM decides which cells get blitted at all, and scrolling as a
  130 REM framebuffer move against scrolling as a model index change.
  140 REM
  150 REM Nothing here is a picture. The screen fills with texture as a
  160 REM side effect, which is only evidence that the writes happened -
  170 REM so every number is written to RESBENC on the share, as
  180 REM key=value, and the rates are derived off the machine where
  190 REM they can be checked rather than squinted at.
  200 REM
  210 REM ARM NATIVE ONLY - copro 15, *ARMBASIC, *PIVDU 2.
  220 :
  230 md%=21:cols%=80
  240 rf$="RESBENC"
  250 REM Each measurement is repeated. The first run, 2026-08-20, returned
  260 REM 9 cs for all four blit variants - a PROC call per cell cannot
  270 REM cost the same as an unrolled loop, so at that size the answer was
  280 REM being lost in the timer rather than measured. Ten repeats put
  290 REM every figure an order of magnitude above the 1 cs tick.
  300 rep%=10
  310 :
  320 fb%=0:sz%=0:pit%=0:stage%=0:rf%=0
  330 ta=0:tb=0:tc=0:td=0:te=0:tf=0:tg=0:th=0:tz=0
  340 ON ERROR PROCerr:END
  350 REM The results file is opened FIRST, before the DIM and before
  360 REM the mode change, so that a failure in either is recorded in it
  370 REM rather than only on a screen nobody kept.
  380 PROCopen
  390 PROCw("[fbbench]")
  400 REM A nonce, so two runs are never mistaken for each other and a
  410 REM file left behind by an earlier run cannot be read as this one.
  420 REM TIME is centiseconds since the machine came up, which differs
  430 REM between runs and needs no clock.
  440 PROCw("run="+STR$(TIME))
  450 REM DIM comes after ON ERROR, not before it: a DIM that will not
  460 REM fit is then our own error with a stage number rather than a
  470 REM bare BASIC message from a program that has not started (9.4).
  480 DIM q% 63,r% 63,font% 256*16,xp% 63
  490 DIM scr% 80*64*4,shd% 80*64*4
  500 :
  510 MODE md%
  520 PROCvars
  530 IF fb%=0 THEN PROCw("fail=no framebuffer address"):PROCshut:END
  540 PROCfill
  550 PROCxp(15,4)
  560 :
  570 stage%=0:PROCz
  580 stage%=1:PROCa
  590 stage%=2:PROCb
  600 stage%=3:PROCc
  610 stage%=4:PROCd
  620 stage%=5:PROCe
  630 stage%=6:PROCf
  640 stage%=7:PROCg
  650 :
  660 PROCreport
  670 PROCfile
  680 PROCw("[end]")
  690 PROCshut
  700 PRINT
  710 PRINT "FBBENCH done - ";rf$;" is on the share for analysis."
  720 END
  730 :
  740 DEF PROCvars
  750 !q%=148:q%!4=150:q%!8=6:q%!12=-1
  760 SYS "OS_ReadVduVariables",q%,r%
  770 fb%=!r%:sz%=r%!4:pit%=r%!8
  780 ENDPROC
  790 :
  800 REM ---- results file ---------------------------------------------
  810 DEF PROCopen
  820 rf%=OPENOUT(rf$)
  830 IF rf%=0 THEN PRINT "cannot open ";rf$;" - results to screen only"
  840 ENDPROC
  850 :
  860 DEF PROCw(s$)
  870 LOCAL i%
  880 IF rf%=0 THEN PRINT s$:ENDPROC
  890 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
  900 BPUT#rf%,13:BPUT#rf%,10
  910 ENDPROC
  920 :
  930 DEF PROCshut
  940 IF rf%<>0 THEN CLOSE#rf%
  950 rf%=0
  960 ENDPROC
  970 :
  980 REM Raw centiseconds and the cell counts they were measured over.
  990 REM No rates - those are arithmetic, and arithmetic belongs where
 1000 REM it can be checked rather than in a BASIC print statement.
 1010 DEF PROCfile
 1020 PROCw("mode="+STR$(md%))
 1030 PROCw("screen=&"+STR$~fb%)
 1040 PROCw("size="+STR$(sz%))
 1050 PROCw("pitch="+STR$(pit%))
 1060 PROCw("reps="+STR$(rep%))
 1070 PROCw("z_emptyloop_cs="+STR$(tz)+" cells=5120")
 1080 PROCw("a_proc_8x8_cs="+STR$(ta)+" cells=5120")
 1090 PROCw("b_inline_8x8_cs="+STR$(tb)+" cells=5120")
 1100 PROCw("c_unrolled_8x8_cs="+STR$(tc)+" cells=5120")
 1110 PROCw("d_inline_8x16_cs="+STR$(td)+" cells=2560")
 1120 PROCw("e_shadow_cs="+STR$(te)+" cells=5120 differed="+STR$(th))
 1130 PROCw("f_scrollmove_cs="+STR$(tf)+" bytes=322560")
 1140 PROCw("g_words_cs="+STR$(tg MOD 1000)+" bytes=8192")
 1150 PROCw("g_bytes_cs="+STR$(tg DIV 1000)+" bytes=8192")
 1160 ENDPROC
 1170 :
 1180 REM Any bytes will do - only the timing is being measured - but a
 1190 REM pattern rather than zeros means the screen shows the work.
 1200 DEF PROCfill
 1210 LOCAL i%
 1220 FOR i%=0 TO 256*16-1:font%?i%=(i%*37) AND 255:NEXT
 1230 FOR i%=0 TO 80*64-1:scr%!(i%*4)=i%:shd%!(i%*4)=i%:NEXT
 1240 shd%!(4000*4)=-1
 1250 ENDPROC
 1260 :
 1270 REM ---- Z: the floor - the loops with the blitting taken out ------
 1280 REM 5120 iterations of the same nest, computing the same glyph
 1290 REM index and nothing else. Whatever A to D cost, this much of it
 1300 REM is the interpreter walking the loop rather than moving pixels,
 1310 REM and without it a difference between the variants cannot be
 1320 REM attributed to anything.
 1330 DEF PROCz
 1340 LOCAL x%,y%,n%,v%
 1350 T=TIME
 1360 FOR n%=1 TO rep%
 1370 FOR y%=0 TO 63
 1380   FOR x%=0 TO 79
 1390     v%=(x%+y%) AND 255
 1400   NEXT
 1410 NEXT
 1420 NEXT
 1430 tz=TIME-T
 1440 ENDPROC
 1450 :
 1460 REM ---- A: a PROC call per cell, 8x8, full 80x64 -----------------
 1470 REM The obvious way to write it, and the one that pays BASIC's
 1480 REM procedure call cost 5120 times.
 1490 DEF PROCa
 1500 LOCAL x%,y%,n%
 1510 T=TIME
 1520 FOR n%=1 TO rep%
 1530 FOR y%=0 TO 63
 1540   FOR x%=0 TO 79
 1550     PROCblit(x%,y%,(x%+y%) AND 255)
 1560   NEXT
 1570 NEXT
 1580 NEXT
 1590 ta=TIME-T
 1600 ENDPROC
 1610 :
 1620 REM ---- B: the same work inline, row loop kept -------------------
 1630 DEF PROCb
 1640 LOCAL x%,y%,a%,f%,b%,n%,i%
 1650 T=TIME
 1660 FOR n%=1 TO rep%
 1670 FOR y%=0 TO 63
 1680   FOR x%=0 TO 79
 1690     a%=fb%+y%*8*pit%+x%*8:f%=font%+((x%+y%) AND 255)*8
 1700     FOR i%=0 TO 7
 1710       b%=f%?i%
 1720       !a%=xp%!((b% DIV 16)*4)
 1730       a%!4=xp%!((b% AND 15)*4)
 1740       a%=a%+pit%
 1750     NEXT
 1760   NEXT
 1770 NEXT
 1780 NEXT
 1790 tb=TIME-T
 1800 ENDPROC
 1810 :
 1820 REM ---- C: inline and unrolled, 8x8 ------------------------------
 1830 REM Eight statements instead of a loop. If this is much faster than
 1840 REM B, the row loop overhead is the renderer's real cost and the
 1850 REM engine should be written this way from the start.
 1860 DEF PROCc
 1870 LOCAL x%,y%,a%,f%,b%,n%
 1880 T=TIME
 1890 FOR n%=1 TO rep%
 1900 FOR y%=0 TO 63
 1910   FOR x%=0 TO 79
 1920     a%=fb%+y%*8*pit%+x%*8:f%=font%+((x%+y%) AND 255)*8
 1930     b%=f%?0:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1940     b%=f%?1:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1950     b%=f%?2:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1960     b%=f%?3:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1970     b%=f%?4:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1980     b%=f%?5:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 1990     b%=f%?6:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4):a%=a%+pit%
 2000     b%=f%?7:!a%=xp%!((b% DIV 16)*4):a%!4=xp%!((b% AND 15)*4)
 2010   NEXT
 2020 NEXT
 2030 NEXT
 2040 tc=TIME-T
 2050 ENDPROC
 2060 :
 2070 REM ---- D: 8x16 cells, 80x32 -------------------------------------
 2080 REM The same pixels, half the cells. Whatever the difference is
 2090 REM between C and D is the per-cell overhead, and it is the whole
 2100 REM geometry argument: 80x32 is more legible AND cheaper if that
 2110 REM overhead dominates, or free if it does not.
 2120 DEF PROCd
 2130 LOCAL x%,y%,a%,f%,b%,n%,i%
 2140 T=TIME
 2150 FOR n%=1 TO rep%
 2160 FOR y%=0 TO 31
 2170   FOR x%=0 TO 79
 2180     a%=fb%+y%*16*pit%+x%*8:f%=font%+((x%+y%) AND 255)*16
 2190     FOR i%=0 TO 15
 2200       b%=f%?i%
 2210       !a%=xp%!((b% DIV 16)*4)
 2220       a%!4=xp%!((b% AND 15)*4)
 2230       a%=a%+pit%
 2240     NEXT
 2250   NEXT
 2260 NEXT
 2270 NEXT
 2280 td=TIME-T
 2290 ENDPROC
 2300 :
 2310 REM ---- E: the shadow compare ------------------------------------
 2320 REM Flush walks every cell and blits only the ones that differ from
 2330 REM what is already on the glass. That walk is paid on every flush
 2340 REM whether anything changed or not, so it has to be cheap.
 2350 DEF PROCe
 2360 LOCAL i%,n%,j%
 2370 T=TIME
 2380 FOR j%=1 TO rep%
 2390 n%=0
 2400 FOR i%=0 TO 80*64-1
 2410   IF scr%!(i%*4)<>shd%!(i%*4) THEN n%=n%+1
 2420 NEXT
 2430 NEXT
 2440 te=TIME-T
 2450 th=n%
 2460 ENDPROC
 2470 :
 2480 REM ---- F: scrolling as a framebuffer move -----------------------
 2490 REM 63 text rows of 8 pixel lines, moved up one row. This is what
 2500 REM NOT decoupling the model from the renderer would cost on every
 2510 REM scrolled line. The model's own scroll is an index change and
 2520 REM costs nothing measurable, which is the point.
 2530 DEF PROCf
 2540 LOCAL l%,s%,d%,i%,j%
 2550 T=TIME
 2560 FOR j%=1 TO rep%
 2570 FOR l%=0 TO 503
 2580   d%=fb%+l%*pit%
 2590   s%=d%+8*pit%
 2600   FOR i%=0 TO 636 STEP 4:d%!i%=s%!i%:NEXT
 2610 NEXT
 2620 NEXT
 2630 tf=TIME-T
 2640 ENDPROC
 2650 :
 2660 REM ---- G: word writes against byte writes -----------------------
 2670 DEF PROCg
 2680 LOCAL i%,a%,j%
 2690 a%=fb%
 2700 T=TIME
 2710 FOR j%=1 TO rep%:FOR i%=0 TO 8188 STEP 4:a%!i%=0:NEXT:NEXT
 2720 tg=TIME-T
 2730 T=TIME
 2740 FOR j%=1 TO rep%:FOR i%=0 TO 8191:a%?i%=0:NEXT:NEXT
 2750 tg=tg+(TIME-T)*1000
 2760 ENDPROC
 2770 :
 2780 REM ---- the numbers ----------------------------------------------
 2790 DEF PROCreport
 2800 LOCAL wr%,by%
 2810 VDU 26:CLS
 2820 wr%=tg MOD 1000:by%=tg DIV 1000
 2830 PRINT "FBBENCH - MODE ";md%;", screen &";~fb%;", pitch ";pit%
 2840 PRINT STRING$(60,"-")
 2850 PRINT "over ";rep%;" repeats of each:"
 2860 PRINT "Z  empty loop           ";tz;" cs"
 2870 PRINT "A  80x64 8x8  PROC/cell ";ta;" cs   ";FNrate(5120*rep%,ta)
 2880 PRINT "B  80x64 8x8  inline    ";tb;" cs   ";FNrate(5120*rep%,tb)
 2890 PRINT "C  80x64 8x8  unrolled  ";tc;" cs   ";FNrate(5120*rep%,tc)
 2900 PRINT "D  80x32 8x16 inline    ";td;" cs   ";FNrate(2560*rep%,td)
 2910 PRINT
 2920 PRINT "E  shadow compare 5120  ";te;" cs   ";th;" cells differed"
 2930 PRINT "F  scroll as screen move ";tf;" cs"
 2940 PRINT "G  8K words ";wr%;" cs   8K bytes ";by%;" cs"
 2950 PRINT STRING$(60,"-")
 2960 PRINT "Repaints per second, worst case, nothing skipped:"
 2970 PRINT "  80x64 best of A-C ";FNps(ta/rep%,tb/rep%,tc/rep%);"   80x32 ";FNps(td/rep%,td/rep%,td/rep%)
 2980 PRINT
 2990 PRINT "The network delivers 3082 bytes/sec (5.5c) and a flush"
 3000 PRINT "happens once per drain, not once per line - so 2 or 3"
 3010 PRINT "repaints a second is a working terminal, and the shadow"
 3020 PRINT "compare means a top refresh blits only what moved."
 3030 PRINT
 3040 PRINT "Record in docs/fbvdu.md. C against D decides the cell size."
 3050 ENDPROC
 3060 :
 3070 DEF FNrate(n%,t)
 3080 IF t<=0 THEN ="too fast to time"
 3090 =STR$(INT(n%*100/t))+" cells/sec"
 3100 :
 3110 DEF FNps(a,b,c)
 3120 LOCAL t
 3130 t=a:IF b<t THEN t=b
 3140 IF c<t THEN t=c
 3150 IF t<=0 THEN ="off scale"
 3160 =STR$(INT(1000/t)/10)
 3170 :
 3180 DEF PROCxp(f%,b%)
 3190 LOCAL n%,i%,m%,a%
 3200 FOR n%=0 TO 15
 3210   a%=xp%+n%*4:m%=8
 3220   FOR i%=0 TO 3
 3230     IF (n% AND m%)<>0 THEN a%?i%=f% ELSE a%?i%=b%
 3240     m%=m% DIV 2
 3250   NEXT
 3260 NEXT
 3270 ENDPROC
 3280 :
 3290 DEF PROCblit(x%,y%,g%)
 3300 LOCAL a%,f%,i%,b%
 3310 a%=fb%+y%*8*pit%+x%*8
 3320 f%=font%+g%*8
 3330 FOR i%=0 TO 7
 3340   b%=f%?i%
 3350   !a%=xp%!((b% DIV 16)*4)
 3360   a%!4=xp%!((b% AND 15)*4)
 3370   a%=a%+pit%
 3380 NEXT
 3390 ENDPROC
 3400 :
 3410 DEF PROCerr
 3420 VDU 26
 3430 PRINT
 3440 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
 3450 REPORT:PRINT
 3460 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
 3470 PROCshut
 3480 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is *PIVDU 2 set?"
 3490 PRINT "DIM space at stage 0 is the host or the emulator, not"
 3500 PRINT "copro 15 - 40K of buffers does not fit in a Master."
 3510 ENDPROC
