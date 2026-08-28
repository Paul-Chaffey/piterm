   10 REM > FBWAY - which read STRATEGY is fastest, under equal conditions
   20 REM
   30 REM   CHAIN "FBWAY"      copro 15, *ARMBASIC, tube on
   40 REM   socat TCP-LISTEN:2323,reuseaddr,fork EXEC:<repo>/tools/feed.sh
   50 REM
   60 REM FBRATE showed the module is effectively ALL OR NOTHING: it answers
   70 REM &1E unless it already holds about as many bytes as you asked for.
   80 REM At 64 bytes only 36 calls in 819 got anything - a 4.4% hit rate -
   90 REM and a 512 byte read never once succeeded in three seconds. Calls
  100 REM per window stayed flat at 777-860 whatever the size, so a call
  110 REM costs about 3.6ms regardless.
  120 REM
  130 REM That is exactly what a peek is for. It buys the count, so the read
  140 REM after it is guaranteed to land instead of guessing and missing
  150 REM nineteen times in twenty.
  160 REM
  170 REM I removed the peek from PTERM on the strength of throughput going
  180 REM from 1611 to 2434 bytes/sec. That comparison is not sound: the
  190 REM figure is bytes per BUSY second, busy time only accumulates in
  200 REM pumps that received something, and the two sessions were shaped
  210 REM differently. It is the same mismatched-denominator mistake I made
  220 REM earlier with the poll rate.
  230 REM
  240 REM So compare the strategies themselves, each for the same three
  250 REM seconds against the same feeder, and count bytes. Strategy 1 runs
  260 REM again at the end; if it does not repeat its own score then the far
  270 REM end drifted and no row here means anything.
  280 REM
  290 REM   1  bare read of 64          what PTERM does now
  300 REM   2  bare read of 32          FBRATE's best size
  310 REM   3  peek, then read exactly what the peek reported
  320 REM   4  peek, then read it in ONE pull however big it is
  330 REM
  340 REM 3 and 4 differ only above 64, which is the whole bulk-pull
  350 REM question: if 4 beats 3 the module will hand over a big block when
  360 REM it has one, and a ROM that pulls bigger blocks has something to
  370 REM work with. If they tie, it never has one, and no amount of
  380 REM cleverness at this end changes that.
  390 :
  400 host$="192.0.2.10":port%=2323
  410 rf$="RESWAY"
  420 mpeek%=1:mnowait%=8
  430 win%=300
  440 top%=1024
  450 :
  460 rf%=0:sock%=-1:err%=0:eof%=FALSE
  470 ON ERROR PROCerr:END
  480 DIM blk% 31, sa% 31, rx% top%
  490 PROCopen
  500 PROCw("[fbway1]")
  510 PROCw("run="+STR$(TIME)+" window_cs="+STR$(win%))
  520 PROCconnect
  530 :
  540 PROCw("way  calls  hits  bytes   cs   bytes_per_sec  biggest")
  550 PROCway(1)
  560 PROCway(2)
  570 PROCway(3)
  580 PROCway(4)
  590 PROCway(1)
  600 :
  610 PROCw("eof="+STR$(eof%))
  620 PROCw("[end]")
  630 PROCshut
  640 PROCclose
  650 PRINT "FBWAY done - ";rf$;" is on the share."
  660 END
  670 :
 1000 REM Run one strategy flat out for win% centiseconds.
 1010 REM ca% counts OSWORD calls, not attempts, so a peek-and-read pair
 1020 REM costs two - otherwise the peeking strategies would be scored as
 1030 REM though the peek were free, which is the whole thing in question.
 1040 DEF PROCway(w%)
 1050 LOCAL t,c
 1060 IF eof% THEN ENDPROC
 1070 ca%=0:hi%=0:by%=0:big%=0
 1080 t=TIME
 1090 REPEAT
 1100   IF w%=1 THEN PROCbare(64)
 1110   IF w%=2 THEN PROCbare(32)
 1120   IF w%=3 THEN PROCpeeked(64)
 1130   IF w%=4 THEN PROCpeeked(top%)
 1140 UNTIL TIME-t>=win% OR eof%
 1150 c=TIME-t
 1160 IF c<1 THEN c=1
 1170 PROCw(FNpad(STR$(w%),5)+FNpad(STR$(ca%),7)+FNpad(STR$(hi%),6)+FNpad(STR$(by%),8)+FNpad(STR$(c),5)+FNpad(STR$(by%*100 DIV c),15)+STR$(big%))
 1180 ENDPROC
 1190 :
 1200 REM One call. Ask for n% and take whatever comes.
 1210 DEF PROCbare(n%)
 1220 LOCAL g%
 1230 g%=FNtake(n%,0)
 1240 IF g%>0 THEN PROCscore(g%)
 1250 IF g%=0 THEN eof%=TRUE
 1260 ENDPROC
 1270 :
 1280 REM Two calls at most. Peek for the count, then pull exactly that,
 1290 REM capped at n%. The peek costs a call and is counted as one.
 1300 DEF PROCpeeked(n%)
 1310 LOCAL a%,g%
 1320 a%=FNtake(n%,mpeek%)
 1330 IF a%=0 THEN eof%=TRUE
 1340 IF a%<1 THEN ENDPROC
 1350 IF a%>n% THEN a%=n%
 1360 g%=FNtake(a%,0)
 1370 IF g%>0 THEN PROCscore(g%)
 1380 IF g%=0 THEN eof%=TRUE
 1390 ENDPROC
 1400 :
 1410 DEF PROCscore(g%)
 1420 hi%=hi%+1:by%=by%+g%
 1430 IF g%>big% THEN big%=g%
 1440 ENDPROC
 1450 :
 1460 REM >0 bytes, 0 end of stream, -2 error with err% holding the code.
 1470 DEF FNtake(n%,f%)
 1480 LOCAL i%
 1490 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1500 blk%?0=20:blk%?1=8:blk%?2=&05
 1510 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=f%+mnowait%
 1520 ca%=ca%+1
 1530 PROCosw
 1540 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1550 err%=blk%?3
 1560 IF err%<>0 THEN =-2
 1570 =blk%!4
 1580 :
 1590 DEF PROCosw
 1600 SYS "OS_Word",&C0,blk%
 1610 ENDPROC
 1620 :
 1630 DEF FNpad(s$,n%)
 1640 IF LEN(s$)>=n% THEN =s$+" "
 1650 =s$+STRING$(n%-LEN(s$)," ")
 1660 :
 1670 DEF PROCconnect
 1680 LOCAL i%,a%,b%,o%
 1690 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1700 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1710 PROCosw
 1720 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1730 sock%=blk%!4
 1740 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1750 sa%?0=16:sa%?1=2
 1760 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1770 a%=1:o%=4
 1780 FOR i%=1 TO 4
 1790   b%=INSTR(host$+".",".",a%)
 1800   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1810   a%=b%+1:o%=o%+1
 1820 NEXT
 1830 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1840 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1850 PROCosw
 1860 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1870 PROCw("connected to "+host$+":"+STR$(port%))
 1880 ENDPROC
 1890 :
 1900 DEF PROCclose
 1910 LOCAL i%
 1920 IF sock%<0 THEN ENDPROC
 1930 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1940 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1950 PROCosw
 1960 sock%=-1
 1970 ENDPROC
 1980 :
 1990 DEF PROCopen
 2000 rf%=OPENOUT(rf$)
 2010 ENDPROC
 2020 :
 2030 DEF PROCw(s$)
 2040 LOCAL i%
 2050 IF rf%=0 THEN ENDPROC
 2060 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 2070 BPUT#rf%,13:BPUT#rf%,10
 2080 ENDPROC
 2090 :
 2100 DEF PROCshut
 2110 IF rf%<>0 THEN CLOSE#rf%
 2120 rf%=0
 2130 ENDPROC
 2140 :
 2150 DEF PROCstop(s$)
 2160 PROCw("fail="+s$)
 2170 PROCw("[end]")
 2180 PROCshut
 2190 PROCclose
 2200 PRINT "FBWAY: ";s$
 2210 END
 2220 :
 2230 DEF PROCerr
 2240 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2250 PROCw("[end]")
 2260 PROCshut
 2270 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2280 REPORT:PRINT
 2290 ENDPROC
