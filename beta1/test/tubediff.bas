   10 REM > TUBEDIFF - find WHICH byte the Tube got wrong, and LOG it
   20 REM
   30 REM   CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "TUBEDIFF"
   40 REM
   50 REM TUBECRC counts corruptions. This identifies them, and writes a
   60 REM record to RESDIFF on the share so the analysis happens off the
   70 REM machine instead of by reading histograms off a photograph.
   80 REM
   90 REM WHAT 2026-08-23 ESTABLISHED, and why this exists in this shape:
  100 REM 16 bad passes in 200 at td=20, 471,480 bad bytes - 29,467 per
  110 REM failing pass out of 65,536. The EOR histogram came out FLAT, all
  120 REM 256 patterns at 1,800-2,200. Flat EOR means the bytes are
  130 REM unrelated, not bit-flipped, so the Tube DROPS A BYTE and the rest
  140 REM of the block shifts up.
  150 REM
  160 REM That is why the byte sum barely moved - deltas of -167 and -43 -
  170 REM while half the file differed: a shift loses one byte and gains
  180 REM whatever lands at the end. TUBECRC's checksum therefore found only
  190 REM 7 of the 16 real failures. It was the wrong detector.
  200 REM
  210 REM So this measures the SHIFT DISTANCE directly. At the first fault it
  220 REM tries k=1..8 in both directions and checks 32 bytes, which says how
  230 REM many bytes went missing rather than merely that some did.
  240 REM
  250 REM The log is APPENDED and CLOSED each time. Keeping it open would be
  260 REM faster, but a hang would lose the buffer and a hang is one of the
  270 REM things being measured. It writes only on failure - about 8% of
  280 REM passes - so the SMB traffic cannot be mistaken for the workload,
  290 REM which is the mistake PTERM's profiler made at 3 seconds flat.
  300 :
  310 bld$="0823b"
  320 f$="TUBEDATA":siz%=65536:ref%=8345686
  330 reps%=200:every%=20:show%=4:maxk%=8:chk%=32
  340 log$="RESDIFF":logon%=TRUE
  350 :
  360 PRINT "TUBEDIFF build ";bld$
  370 PRINT "file=";f$;" bytes=";siz%;" ref sum=";ref%
  380 PRINT "log=";log$;" passes=";reps%
  390 INPUT "tube_delay for this run ",td%
  400 PRINT
  410 :
  420 DIM r% siz%,t% siz%,gotc%(255),eorc%(255)
  430 :
  440 REM The reference crosses the Tube too. A corrupt one would make every
  450 REM later pass look wrong, so it is checked and reloaded until right.
  460 tries%=0
  470 REPEAT
  480   tries%=tries%+1
  490   OSCLI("LOAD "+f$+" "+STR$~r%)
  500   s%=0
  510   FOR i%=0 TO siz%-1:s%=s%+r%?i%:NEXT
  520 UNTIL s%=ref%
  530 PRINT "reference verified after ";tries%;" load(s)"
  540 PROClog("# TUBEDIFF "+bld$+" td="+STR$(td%)+" file="+f$+" siz="+STR$(siz%)+" ref="+STR$(ref%)+" reftries="+STR$(tries%))
  550 PROClog("# pass ndiff first want got shift sum")
  560 PRINT
  570 :
  580 n%=0:bad%=0:byt%=0:lost%=0:dup%=0:other%=0:t0%=TIME
  590 REPEAT
  600   t%?0=0:t%?(siz%-1)=0
  610   OSCLI("LOAD "+f$+" "+STR$~t%)
  620   d%=0:first%=-1:s%=0
  630   FOR i%=0 TO siz%-1
  640     s%=s%+t%?i%
  650     IF r%?i%<>t%?i% THEN PROCdiff(i%,d%):d%=d%+1
  660   NEXT
  670   n%=n%+1
  680   IF d%>0 THEN PROCfail(d%,s%)
  690   IF n% MOD every%=0 THEN PROCsay
  700 UNTIL n%>=reps%
  710 PROCsay
  720 PROChist
  730 END
  740 :
  750 DEF PROCdiff(i%,d%)
  760 LOCAL w%,g%,e%
  770 w%=r%?i%:g%=t%?i%:e%=w% EOR g%
  780 byt%=byt%+1
  790 gotc%(g%)=gotc%(g%)+1
  800 eorc%(e%)=eorc%(e%)+1
  810 IF d%=0 THEN first%=i%
  820 IF d%<show% THEN PRINT "  off=";i%;" want=&";~w%;" got=&";~g%;" eor=&";~e%
  830 ENDPROC
  840 :
  850 REM One line per failing pass, plus the bytes either side of the fault
  860 REM so the alignment can be re-derived off-machine rather than trusted.
  870 DEF PROCfail(d%,s%)
  880 LOCAL k%
  890 bad%=bad%+1
  900 k%=FNshift(first%)
  910 IF k%>0 THEN lost%=lost%+1
  920 IF k%<0 THEN dup%=dup%+1
  930 IF k%=0 THEN other%=other%+1
  940 PRINT "pass ";n%;" ndiff=";d%;" first=";first%;" shift=";k%
  950 PROClog(STR$(n%)+" "+STR$(d%)+" "+STR$(first%)+" "+STR$~(r%?first%)+" "+STR$~(t%?first%)+" "+STR$(k%)+" "+STR$(s%))
  960 PROClog("  want "+FNhex(r%,first%-8,24))
  970 PROClog("  got  "+FNhex(t%,first%-8,24))
  980 ENDPROC
  990 :
 1000 REM How far did the block move? Try each k in both directions and
 1010 REM require chk% consecutive bytes to agree, which no coincidence
 1020 REM survives. Positive k means k bytes were LOST before this point.
 1030 DEF FNshift(i%)
 1040 LOCAL k%,j%,ok%
 1050 IF i%<0 THEN =0
 1060 FOR k%=1 TO maxk%
 1070   ok%=TRUE
 1080   FOR j%=0 TO chk%-1
 1090     IF i%+j%+k%>siz%-1 THEN ok%=FALSE
 1100     IF ok% THEN IF t%?(i%+j%)<>r%?(i%+j%+k%) THEN ok%=FALSE
 1110   NEXT
 1120   IF ok% THEN =k%
 1130 NEXT
 1140 FOR k%=1 TO maxk%
 1150   ok%=TRUE
 1160   FOR j%=0 TO chk%-1
 1170     IF i%+j%-k%<0 THEN ok%=FALSE
 1180     IF ok% THEN IF t%?(i%+j%)<>r%?(i%+j%-k%) THEN ok%=FALSE
 1190   NEXT
 1200   IF ok% THEN =-k%
 1210 NEXT
 1220 =0
 1230 :
 1240 DEF FNhex(b%,o%,ln%)
 1250 LOCAL j%,h$
 1260 IF o%<0 THEN o%=0
 1270 h$=""
 1280 FOR j%=0 TO ln%-1
 1290   IF o%+j%<=siz%-1 THEN h$=h$+RIGHT$("0"+STR$~(b%?(o%+j%)),2)
 1300 NEXT
 1310 =STR$(o%)+" "+h$
 1320 :
 1330 DEF PROClog(s$)
 1340 LOCAL h%,j%
 1350 IF NOT logon% THEN ENDPROC
 1360 h%=OPENUP(log$)
 1370 IF h%=0 THEN h%=OPENOUT(log$)
 1380 IF h%=0 THEN ENDPROC
 1390 PTR#h%=EXT#h%
 1400 FOR j%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,j%,1)):NEXT
 1410 BPUT#h%,13
 1420 CLOSE#h%
 1430 ENDPROC
 1440 :
 1450 DEF PROCsay
 1460 LOCAL e%
 1470 e%=TIME-t0%+1
 1480 PRINT "td=";td%;" pass=";n%;" badpass=";bad%;" badbytes=";byt%;" secs=";e%/100
 1490 ENDPROC
 1500 :
 1510 DEF PROChist
 1520 LOCAL i%
 1530 PROClog("# eor histogram")
 1540 FOR i%=0 TO 255
 1550   IF eorc%(i%)>0 THEN PROClog("#  eor "+STR$~i%+" "+STR$(eorc%(i%)))
 1560 NEXT
 1570 PROClog("# summary td="+STR$(td%)+" passes="+STR$(n%)+" badpass="+STR$(bad%)+" badbytes="+STR$(byt%)+" lost="+STR$(lost%)+" dup="+STR$(dup%)+" other="+STR$(other%))
 1580 PRINT
 1590 PRINT "first-fault kind: lost=";lost%;" repeated=";dup%;" other=";other%
 1600 PRINT "DONE td=";td%;" passes=";n%;" badpass=";bad%;" badbytes=";byt%
 1610 PRINT "written to ";log$
 1620 ENDPROC
