   10 REM > FBRATE - sustained bytes/sec at each read size
   20 REM
   30 REM   CHAIN "FBRATE"     copro 15, *ARMBASIC, tube on
   40 REM   socat TCP-LISTEN:2323,reuseaddr,fork EXEC:<repo>/tools/feed.sh
   50 REM
   60 REM FBCOST answered the two questions it was built for and then could
   70 REM not settle the one that matters.
   80 REM
   90 REM It established that the module never REFUSES - refused=0 on every
  100 REM row - and that reads above 64 come back &1E, "would block", meaning
  110 REM "not that many bytes yet" rather than "too big". A 128 byte read
  120 REM returned a full 128 the two times the bytes were there. So 64 was
  130 REM never a cap and the spec's "128 is the Tube control-block cap" is
  140 REM wrong.
  150 REM
  160 REM It also costed a call: about 3.2ms fixed plus 56us a byte, so at 64
  170 REM bytes very nearly half of every read is per-call overhead. That
  180 REM argues loudly for pulling more per call.
  190 REM
  200 REM But the whole sweep averaged 2136 bytes/sec - almost exactly what
  210 REM PTERM gets - while the size 64 row alone ran at 6192. Those two
  220 REM readings have completely different consequences:
  230 REM
  240 REM   Bigger reads really are faster -> a peek-then-bulk-pull design
  250 REM   wins, and it is worth building.
  260 REM   The module only makes data available at ~2.2KB/sec -> the fast
  270 REM   windows were draining a backlog, nothing on the BBC side can
  280 REM   help, and that is simply the ceiling of this hardware.
  290 REM
  300 REM FBCOST cannot separate them because it timed a fixed number of
  310 REM CALLS. A size that finds nothing finishes its 50 calls in 16cs and
  320 REM leaves the socket a third of a second to refill for the next size,
  330 REM which is why size 16 scored zero and size 32 scored 25 immediately
  340 REM after. The sizes were not measured under equal conditions.
  350 REM
  360 REM So measure over a fixed DURATION instead. Every size gets the same
  370 REM wall clock, reads back to back for all of it, and the answer is
  380 REM bytes per second - the number we actually care about.
  390 :
  400 host$="192.0.2.10":port%=2323
  410 rf$="RESRATE"
  420 mnowait%=8
  430 win%=300
  440 top%=1024
  450 :
  460 rf%=0:sock%=-1:err%=0:eof%=FALSE
  470 ON ERROR PROCerr:END
  480 DIM blk% 31, sa% 31, rx% top%, tx% top%
  490 PROCopen
  500 PROCw("[fbrate1]")
  510 PROCw("run="+STR$(TIME)+" window_cs="+STR$(win%))
  520 PROCconnect
  530 :
  540 REM Each size gets the same three seconds, reading flat out.
  550 PROCw("size  calls  hits  bytes   cs   bytes_per_sec  wouldblock")
  560 PROCrate(1)
  570 PROCrate(8)
  580 PROCrate(32)
  590 PROCrate(64)
  600 PROCrate(128)
  610 PROCrate(256)
  620 PROCrate(512)
  630 REM 64 again at the end. If it does not repeat its first score the far
  640 REM end is what varied, not the read size, and none of the rows mean
  650 REM anything.
  660 PROCrate(64)
  670 :
  680 PROCw("eof="+STR$(eof%))
  690 PROCw("[end]")
  700 PROCshut
  710 PROCclose
  720 PRINT "FBRATE done - ";rf$;" is on the share."
  730 END
  740 :
 1000 REM Read sz% back to back for win% centiseconds and report the rate.
 1010 DEF PROCrate(sz%)
 1020 LOCAL g%,t,c
 1030 IF eof% THEN ENDPROC
 1040 ca%=0:hi%=0:by%=0:wb%=0:no%=0
 1050 t=TIME
 1060 REPEAT
 1070   g%=FNtake(sz%)
 1080   ca%=ca%+1
 1090   IF g%>0 THEN hi%=hi%+1:by%=by%+g%
 1100   IF g%=0 THEN eof%=TRUE
 1110   IF g%=-2 AND err%=&1E THEN wb%=wb%+1
 1120   IF g%=-2 AND err%<>&1E THEN no%=no%+1
 1130 UNTIL TIME-t>=win% OR eof%
 1140 c=TIME-t
 1150 IF c<1 THEN c=1
 1160 PROCw(FNpad(STR$(sz%),6)+FNpad(STR$(ca%),7)+FNpad(STR$(hi%),6)+FNpad(STR$(by%),8)+FNpad(STR$(c),5)+FNpad(STR$(by%*100 DIV c),15)+FNpad(STR$(wb%),7)+"bad="+STR$(no%))
 1170 ENDPROC
 1180 :
 1190 REM >0 bytes, 0 end of stream, -2 error with err% holding the code.
 1200 DEF FNtake(n%)
 1210 PROCzap
 1220 blk%?0=20:blk%?1=8:blk%?2=&05
 1230 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mnowait%
 1240 PROCosw
 1250 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1260 err%=blk%?3
 1270 IF err%<>0 THEN =-2
 1280 =blk%!4
 1290 :
 1300 DEF PROCzap
 1310 LOCAL i%
 1320 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1330 ENDPROC
 1340 :
 1350 DEF PROCosw
 1360 SYS "OS_Word",&C0,blk%
 1370 ENDPROC
 1380 :
 1390 DEF FNpad(s$,n%)
 1400 IF LEN(s$)>=n% THEN =s$+" "
 1410 =s$+STRING$(n%-LEN(s$)," ")
 1420 :
 1430 DEF PROCconnect
 1440 LOCAL i%,a%,b%,o%
 1450 PROCzap
 1460 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1470 PROCosw
 1480 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1490 sock%=blk%!4
 1500 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1510 sa%?0=16:sa%?1=2
 1520 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1530 a%=1:o%=4
 1540 FOR i%=1 TO 4
 1550   b%=INSTR(host$+".",".",a%)
 1560   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1570   a%=b%+1:o%=o%+1
 1580 NEXT
 1590 PROCzap
 1600 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1610 PROCosw
 1620 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1630 PROCw("connected to "+host$+":"+STR$(port%))
 1640 ENDPROC
 1650 :
 1660 DEF PROCclose
 1670 IF sock%<0 THEN ENDPROC
 1680 PROCzap
 1690 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1700 PROCosw
 1710 sock%=-1
 1720 ENDPROC
 1730 :
 1740 DEF PROCopen
 1750 rf%=OPENOUT(rf$)
 1760 ENDPROC
 1770 :
 1780 DEF PROCw(s$)
 1790 LOCAL i%
 1800 IF rf%=0 THEN ENDPROC
 1810 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1820 BPUT#rf%,13:BPUT#rf%,10
 1830 ENDPROC
 1840 :
 1850 DEF PROCshut
 1860 IF rf%<>0 THEN CLOSE#rf%
 1870 rf%=0
 1880 ENDPROC
 1890 :
 1900 DEF PROCstop(s$)
 1910 PROCw("fail="+s$)
 1920 PROCw("[end]")
 1930 PROCshut
 1940 PROCclose
 1950 PRINT "FBRATE: ";s$
 1960 END
 1970 :
 1980 DEF PROCerr
 1990 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2000 PROCw("[end]")
 2010 PROCshut
 2020 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2030 REPORT:PRINT
 2040 ENDPROC
