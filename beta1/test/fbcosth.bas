   10 REM > FBCOST - what really limits a socket read, and is 64 a real cap?
   20 REM
   30 REM   CHAIN "FBCOST"     copro 15, *ARMBASIC, tube on
   40 REM   CHAIN "FBCOSTH"    the HOST, no copro - same probe, no Tube
   50 REM
   60 REM Two questions this settles, neither of which has ever been measured.
   70 REM
   80 REM 1. WHY 64? The spec calls 128 "the Tube control-block cap" but that
   90 REM    is an assumption somebody wrote down, not a measurement. If the
  100 REM    HOST - where there is no Tube at all - reads 1024 happily and the
  110 REM    co-processor will not, the limit is the Tube path and a sideways
  120 REM    ROM can lift it: read big into host RAM, hand over one block.
  130 REM    If the host refuses above 128 too, the limit is inside the module
  140 REM    and a ROM can only amortise the crossing, not the module.
  150 REM
  160 REM 2. FIXED OR PER BYTE? If the cost is mostly per call, one big pull
  170 REM    after a cheap peek is a large win and is worth building. If it is
  180 REM    mostly per byte, the pull size hardly matters and 2400 b/s is
  190 REM    about the ceiling of this hardware.
  200 REM
  210 REM Test A times reads of each size against a socket kept FULL, so a
  220 REM read of n returns n and the curve is clean. The slope is the per
  230 REM byte cost and the intercept is the per call cost.
  240 REM Test B asks for a big read when only a trickle has arrived, to tell
  250 REM cost per byte REQUESTED from cost per byte RETURNED. PTERM always
  260 REM asks for 64, so if cost follows the request it pays full price on
  270 REM every poll.
  280 REM Test C times polls that return nothing - the cost of the peek in a
  290 REM peek-then-pull design, and the cost of idling.
  300 REM Test D times SENDS. NON-BLOCKING now, and no 256 byte send: with
  315 REM flags=0 a 256 byte send to a far end that is not reading NEVER
  316 REM RETURNS, which is what hung the machine and cost a BREAK last time.
  317 REM Test D times SENDS, because killing a flooding top is slow and the
  310 REM transmit path has never been measured at all. Note PTERM sends with
  320 REM flags=0, ie BLOCKING, which under a full receive buffer may be a
  330 REM large part of that.
  340 REM
  350 REM Needs a feeder with plenty to say and a definite end:
  360 REM
  370 REM   socat TCP-LISTEN:2323,reuseaddr,fork SYSTEM:'yes ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 | head -c 900000'
  380 :
  390 host$="192.0.2.10":port%=2323
  400 rf$="RESCOSH"
  410 mpeek%=1:mnowait%=8
  420 reps%=30
  430 top%=256
  440 :
  450 rf%=0:sock%=-1:err%=0:eof%=FALSE
  460 ON ERROR PROCerr:END
  470 DIM blk% 31, sa% 31, rx% top%, tx% top%
  480 PROCopen
  490 PROCw("[fbcost1]")
  500 PROCw("run="+STR$(TIME)+" reps="+STR$(reps%)+" top="+STR$(top%))
  510 PROCw("himem="+STR$~(HIMEM))
  520 PROCconnect
  530 :
  540 PROCw("test size calls gotdata bytes cs refused wouldblock")
  550 sz%=1
  560 FOR p%=0 TO 10
  570   IF NOT eof% AND sz%<=top% THEN PROCtime(sz%,"A")
  580   sz%=sz%*2
  590 NEXT
  600 :
  610 IF NOT eof% THEN PROCdrain
  620 IF NOT eof% THEN PROCtrickle(8)
  630 IF NOT eof% THEN PROCtrickle(64)
  640 IF NOT eof% THEN PROCtrickle(1024)
  650 :
  660 PROCdrain
  670 PROCtime(1024,"C")
  680 PROCtime(64,"C")
  690 PROCtime(1,"C")
  700 :
  710 PROCsend(1)
  720 PROCsend(16)
  730 PROCsend(64)
  750 :
  760 PROCw("eof="+STR$(eof%))
  770 PROCw("[end]")
  780 PROCshut
  790 PROCclose
  800 PRINT "FBCOST done - ";rf$;" is on the share."
  810 END
  820 :
 1000 REM Time reps% reads of exactly sz%. Calls that returned data are
 1010 REM counted apart from calls that returned nothing, because averaging
 1020 REM the two together would hide the whole answer.
 1030 DEF PROCtime(sz%,tag$)
 1040 LOCAL i%,g%,t
 1050 ok%=0:by%=0:no%=0:zz%=0
 1060 t=TIME
 1070 FOR i%=1 TO reps%
 1080   g%=FNtake(sz%)
 1090   IF g%>0 THEN ok%=ok%+1:by%=by%+g%
 1100   IF g%=0 THEN eof%=TRUE:i%=reps%
 1110   IF g%=-2 AND err%=&1E THEN zz%=zz%+1
 1120   IF g%=-2 AND err%<>&1E THEN no%=no%+1
 1130 NEXT
 1140 PROCrow(tag$,sz%,TIME-t)
 1150 ENDPROC
 1160 :
 1170 REM Same, but with a gap before each call so only a trickle has arrived
 1180 REM by the time the read is made. The gap is OUTSIDE the timer.
 1190 DEF PROCtrickle(sz%)
 1200 LOCAL i%,g%,t,c
 1210 ok%=0:by%=0:no%=0:zz%=0:c=0
 1220 FOR i%=1 TO reps%
 1230   PROCwait
 1240   t=TIME
 1250   g%=FNtake(sz%)
 1260   c=c+(TIME-t)
 1270   IF g%>0 THEN ok%=ok%+1:by%=by%+g%
 1280   IF g%=0 THEN eof%=TRUE:i%=reps%
 1290   IF g%=-2 AND err%=&1E THEN zz%=zz%+1
 1300   IF g%=-2 AND err%<>&1E THEN no%=no%+1
 1310 NEXT
 1320 PROCrow("B",sz%,c)
 1330 ENDPROC
 1340 :
 1350 REM Time sends. PTERM sends blocking, so this is what a keystroke costs
 1360 REM while the receive side is backed up.
 1370 DEF PROCsend(sz%)
 1380 LOCAL i%,t
 1390 ok%=0:by%=0:no%=0:zz%=0
 1400 FOR i%=0 TO sz%-1:tx%?i%=65:NEXT
 1410 t=TIME
 1420 FOR i%=1 TO reps%
 1430   PROCzap
 1440   blk%?0=20:blk%?1=8:blk%?2=&08
 1450   blk%!4=sock%:blk%!8=tx%:blk%!12=sz%:blk%!16=mnowait%
 1460   PROCosw
 1470   IF blk%?3<>0 THEN no%=no%+1
 1480   IF blk%?3=0 THEN ok%=ok%+1:by%=by%+blk%!4
 1490 NEXT
 1500 PROCrow("D",sz%,TIME-t)
 1510 ENDPROC
 1520 :
 1530 DEF PROCrow(tag$,sz%,c)
 1540 PROCw(FNpad(tag$,5)+FNpad(STR$(sz%),5)+FNpad(STR$(reps%),6)+FNpad(STR$(ok%),8)+FNpad(STR$(by%),7)+FNpad(STR$(c),5)+FNpad(STR$(no%),8)+STR$(zz%))
 1550 ENDPROC
 1560 :
 1570 DEF PROCwait
 1580 LOCAL t
 1590 t=TIME
 1600 REPEAT UNTIL TIME-t>1
 1610 ENDPROC
 1620 :
 1630 REM Read until the socket says there is nothing left. Bounded, so a
 1640 REM feeder that never stops cannot hang the probe here.
 1650 DEF PROCdrain
 1660 LOCAL i%,g%
 1670 FOR i%=1 TO 3000
 1680   g%=FNtake(top%)
 1690   IF g%=0 THEN eof%=TRUE:i%=3000
 1700   IF g%=-2 THEN i%=3000
 1710 NEXT
 1720 ENDPROC
 1730 :
 1740 REM >0 bytes read, 0 end of stream, -2 error with err% holding the code.
 1750 REM &1E is the module's would-block and is not a refusal.
 1760 DEF FNtake(n%)
 1770 PROCzap
 1780 blk%?0=20:blk%?1=8:blk%?2=&05
 1790 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mnowait%
 1800 PROCosw
 1810 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1820 err%=blk%?3
 1830 IF err%<>0 THEN =-2
 1840 =blk%!4
 1850 :
 1860 DEF PROCzap
 1870 LOCAL i%
 1880 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1890 ENDPROC
 1900 :
 1910 REM The one line that differs between the two builds. FBCOSTH swaps it
 1920 REM for the 6502 CALL &FFF1 form, because BASIC IV has no SYS at all.
 1930 DEF PROCosw
 1940 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1950 ENDPROC
 1960 :
 1970 DEF FNpad(s$,n%)
 1980 IF LEN(s$)>=n% THEN =s$+" "
 1990 =s$+STRING$(n%-LEN(s$)," ")
 2000 :
 2010 DEF PROCconnect
 2020 LOCAL i%,a%,b%,o%
 2030 PROCzap
 2040 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 2050 PROCosw
 2060 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 2070 sock%=blk%!4
 2080 FOR i%=0 TO 15:sa%?i%=0:NEXT
 2090 sa%?0=16:sa%?1=2
 2100 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 2110 a%=1:o%=4
 2120 FOR i%=1 TO 4
 2130   b%=INSTR(host$+".",".",a%)
 2140   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 2150   a%=b%+1:o%=o%+1
 2160 NEXT
 2170 PROCzap
 2180 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 2190 PROCosw
 2200 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 2210 PROCw("connected to "+host$+":"+STR$(port%))
 2220 ENDPROC
 2230 :
 2240 DEF PROCclose
 2250 IF sock%<0 THEN ENDPROC
 2260 PROCzap
 2270 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 2280 PROCosw
 2290 sock%=-1
 2300 ENDPROC
 2310 :
 2320 DEF PROCopen
 2330 rf%=OPENOUT(rf$)
 2340 ENDPROC
 2350 :
 2360 DEF PROCw(s$)
 2370 LOCAL i%
 2380 IF rf%=0 THEN ENDPROC
 2390 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 2400 BPUT#rf%,13:BPUT#rf%,10
 2410 ENDPROC
 2420 :
 2430 DEF PROCshut
 2440 IF rf%<>0 THEN CLOSE#rf%
 2450 rf%=0
 2460 ENDPROC
 2470 :
 2480 DEF PROCstop(s$)
 2490 PROCw("fail="+s$)
 2500 PROCw("[end]")
 2510 PROCshut
 2520 PROCclose
 2530 PRINT "FBCOST: ";s$
 2540 END
 2550 :
 2560 DEF PROCerr
 2570 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2580 PROCw("[end]")
 2590 PROCshut
 2600 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2610 REPORT:PRINT
 2620 ENDPROC
