   10 REM > FBBATT - phase 1 of the battery-backup test: ARM IT
   20 REM
   30 REM   co-processor OFF (or it does not matter):
   40 REM       NEW   then  *EXEC FBBATT   then  RUN
   50 REM
   60 REM The RTC is HOST hardware. OSWORD &0F across the Tube gave error
   70 REM 16 (see FBSETTH), so this runs on the host where OSWORD &0E and
   80 REM &0F are plain calls through &FFF1.
   90 REM
  100 REM Battery backup is retention across a POWER CUT, so no single
  110 REM program can test it. This is the first half:
  120 REM
  130 REM   1. record what the chip holds now       (*STATUS, OSWORD &0E)
  140 REM   2. write a known time                   (OSWORD &0F TYPE 24)
  150 REM   3. write two harmless CMOS markers      (*CONFIGURE)
  160 REM   4. read both back IMMEDIATELY
  170 REM
  180 REM Step 4 answers a question the battery cannot: is the chip
  190 REM WRITABLE at all with the machine powered? On 2026-08-21 it was
  200 REM not - spec 5.5b-quinquies - and a chip that will not take a
  210 REM write with 5V present has nothing to do with retention.
  220 REM
  230 REM Then power OFF at the mains for at least five minutes and run
  240 REM FBBATT2. A Ctrl-Break is NOT a test: the chip never lost power,
  250 REM so anything held across a reset says nothing about the battery.
  260 REM
  270 REM The markers are DELAY and REPEAT - keyboard auto-repeat - chosen
  280 REM because nothing else reads them, they take any byte, they show
  290 REM in *STATUS by name, and the values here are ones no default
  300 REM produces. Both currently read 0.
  305 REM OSWORD &0F HAS NO TYPE 0, AND TYPE 8 IS TIME ONLY. The three
  306 REM reason codes are 8 (time, "hh:mm:ss" at +1), 15 (date, "ddd,nn
  307 REM mmm yyyy" at +1) and 24 (both: the date at +1 to +15, "." at
  308 REM +16, the time at +17 to +24). FBSETT and FBSETTH used 8 and 0
  309 REM with the whole 24-character string, so type 8 read "Fr" as the
  310 REM hours and type 0 is not a function at all. Neither ever asked
  311 REM the chip to do anything - see spec 5.5b-octies. The string
  312 REM below is already exactly the type 24 layout, and is the same 24
  313 REM characters OSWORD &0E hands back.
  314 :
  320 t$="Fri,21 Aug 2026.22:17:41"
  330 dly%=45:rpt%=17
  340 rf$="RESBAT1"
  350 ON ERROR PROCerr:END
  360 DIM blk% 31,clk% 31
  370 PRINT "spooling to ";rf$
  380 OSCLI("SPOOL "+rf$)
  390 PRINT "== FBBATT phase 1 =="
  400 PRINT "== WROTE == ";t$
  410 PRINT "== MARKERS == Delay ";dly%;" Repeat ";rpt%
  420 PRINT "== CLOCK BEFORE == ";FNclock
  430 PRINT "== STATUS BEFORE =="
  440 OSCLI("STATUS")
  450 PROCset(24,t$)
  460 PRINT "== CLOCK AFTER 24 == ";FNclock
  470 IF FNyear(FNclock)=FNyear(t$) THEN 480
  472 REM 24 did not take. Try the two halves separately - that says
  474 REM whether it is the date registers, the time registers or both,
  476 REM and each is a different fault.
  477 PROCset(15,LEFT$(t$,15)):PRINT "== CLOCK AFTER 15 == ";FNclock
  478 PROCset(8,MID$(t$,17,8)):PRINT "== CLOCK AFTER 8 == ";FNclock
  480 OSCLI("CONFIGURE DELAY "+STR$(dly%))
  490 OSCLI("CONFIGURE REPEAT "+STR$(rpt%))
  500 PRINT "== STATUS AFTER =="
  510 OSCLI("STATUS")
  520 PRINT "== END =="
  530 OSCLI("SPOOL")
  540 c$=FNclock
  550 PRINT
  560 IF FNyear(c$)=FNyear(t$) THEN PRINT "CLOCK WRITE TOOK - now ";c$ ELSE PRINT "CLOCK WRITE IGNORED - still ";c$
  570 PRINT "Check Delay/Repeat in the STATUS AFTER block above: 45 and 17"
  580 PRINT "means CMOS took the write, 0 and 0 means it did not."
  590 PRINT
  600 PRINT "If both writes took: power OFF AT THE MAINS for five minutes"
  610 PRINT "or more, power on, and RUN FBBATT2."
  620 PRINT "If neither took, the chip is not writable and the battery"
  630 PRINT "question does not arise yet - stop here."
  640 END
  650 :
 1000 DEF PROCset(ty%,s$)
 1010 LOCAL i%
 1020 FOR i%=0 TO 31:blk%?i%=0:NEXT
 1030 blk%?0=ty%
 1040 FOR i%=1 TO LEN(s$):blk%?i%=ASC(MID$(s$,i%,1)):NEXT
 1050 blk%?(LEN(s$)+1)=13
 1060 A%=&0F:X%=blk% AND 255:Y%=blk% DIV 256
 1070 CALL &FFF1
 1080 ENDPROC
 1090 :
 1100 REM OSWORD &0E type 0: the clock as "Day,DD Mon YYYY.HH:MM:SS"+CR,
 1110 REM which is what *TIME prints, but in a string this can compare.
 1120 DEF FNclock
 1130 clk%?0=0
 1140 A%=&0E:X%=clk% AND 255:Y%=clk% DIV 256
 1150 CALL &FFF1
 1160 =$clk%
 1170 :
 1180 REM Characters 14 and 15 are the two-digit year, which is all the
 1190 REM chip holds. THIS MOS ALWAYS PRINTS THE CENTURY AS 19, so a
 1195 REM successful write of 2026 reads back as 1926 and comparing four
 1196 REM characters would call it a failure (proved under b-em, spec
 1197 REM 5.5b-decies). A dead chip reads "7B" here, which is not decimal.
 1200 DEF FNyear(s$)
 1210 =MID$(s$,14,2)
 1220 :
 1230 DEF PROCerr
 1240 OSCLI("SPOOL")
 1250 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1260 REPORT:PRINT
 1270 ENDPROC
