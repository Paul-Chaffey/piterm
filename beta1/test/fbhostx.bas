   10 REM > FBHOST - is the 3.6ms call the TUBE, or the MODULE?
   20 REM
   30 REM   *EXEC FBHOST   then RUN     on the HOST, co-processor OFF
   40 REM   CHAIN "FBHOSTA"             on copro 15, *ARMBASIC
   50 REM
   60 REM The last open question. Socket_Recv will not return more than
   70 REM about 64 bytes however much is queued - a real session leaves
   80 REM 2-4KB waiting and it still hands over 64 - so no strategy on the
   90 REM co-processor can drain a burst faster. A sideways ROM cannot
  100 REM change that either. But it COULD do sixteen 64 byte recvs host
  110 REM side and hand the co-processor one 1KB block, paying the Tube
  120 REM crossing once instead of sixteen times.
  130 REM
  140 REM Worth building only if the Tube is most of the 3.6ms. So measure
  150 REM the same two things on both sides and compare:
  160 REM
  170 REM   an EMPTY poll   - pure call overhead, no data moved
  180 REM   a FULL 64 read  - overhead plus moving 64 bytes
  190 REM
  200 REM If the host polls at about 3ms too, the Tube is nearly free, the
  210 REM module owns the cost, and a ROM buys nothing. If the host is well
  220 REM under 1ms, the Tube is most of it and a ROM is worth building.
  230 REM
  240 REM Deliberately small. FBCOSTH locked the machine up because its
  250 REM drain loop was sized for a co-processor that is ten times faster
  260 REM per call, and 4000 host reads at 41ms is two and a half minutes.
  270 REM There is no drain here and every loop is a fixed short count.
  280 REM
  290 REM Two listeners, because timing an empty poll needs a socket with
  300 REM nothing on it and draining a live feeder to get one is what hung
  310 REM the last attempt:
  320 REM
  330 REM   socat TCP-LISTEN:2323,reuseaddr,fork EXEC:<repo>/tools/feed.sh
  340 REM   socat TCP-LISTEN:2324,reuseaddr,fork EXEC:<repo>/tools/quiet.sh
  350 :
  360 host$="192.0.2.10"
  370 rf$="RESHOST"
  380 mnowait%=8
  390 reps%=100
  400 :
  410 rf%=0:sock%=-1:err%=0
  420 ON ERROR PROCerr:END
  430 DIM blk% 31, sa% 31, rx% 127
  440 PROCopen
  450 PROCw("[fbhost1]")
  460 PROCw("run="+STR$(TIME)+" reps="+STR$(reps%))
  470 PROCw("himem="+STR$~(HIMEM))
  480 :
  490 REM Quiet socket first: every call returns nothing, so this is pure
  500 REM per-call overhead with no data moved at all.
  510 PROCconnect(2324)
  520 PROCtime("empty_poll",64)
  530 PROCclose
  540 :
  550 REM Then the feeder, where calls do move bytes.
  560 PROCconnect(2323)
  570 PROCtime("read64",64)
  580 PROCtime("read1",1)
  590 PROCclose
  600 :
  610 PROCw("[end]")
  620 PROCshut
  630 PRINT "FBHOST done - ";rf$;" is on the share."
  640 END
  650 :
 1000 REM reps% calls of one size, timed as a batch. cs is centiseconds for
 1010 REM the whole batch, so per-call microseconds is cs*10000/reps%.
 1020 DEF PROCtime(tag$,sz%)
 1030 LOCAL i%,g%,t,c
 1040 ok%=0:by%=0:zz%=0:no%=0
 1050 t=TIME
 1060 FOR i%=1 TO reps%
 1070   g%=FNtake(sz%)
 1080   IF g%>0 THEN ok%=ok%+1:by%=by%+g%
 1090   IF g%=-2 AND err%=&1E THEN zz%=zz%+1
 1100   IF g%=-2 AND err%<>&1E THEN no%=no%+1
 1110 NEXT
 1120 c=TIME-t
 1130 IF c<1 THEN c=1
 1140 PROCw(tag$+" size="+STR$(sz%)+" calls="+STR$(reps%)+" got="+STR$(ok%)+" bytes="+STR$(by%)+" cs="+STR$(c)+" us_per_call="+STR$(c*10000 DIV reps%)+" wouldblock="+STR$(zz%)+" bad="+STR$(no%))
 1150 ENDPROC
 1160 :
 1170 DEF FNtake(n%)
 1180 LOCAL i%
 1190 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1200 blk%?0=20:blk%?1=8:blk%?2=&05
 1210 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mnowait%
 1220 PROCosw
 1230 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1240 err%=blk%?3
 1250 IF err%<>0 THEN =-2
 1260 =blk%!4
 1270 :
 1280 DEF PROCosw
 1290 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1300 ENDPROC
 1310 :
 1320 DEF PROCconnect(port%)
 1330 LOCAL i%,a%,b%,o%
 1340 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1350 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1360 PROCosw
 1370 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1380 sock%=blk%!4
 1390 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1400 sa%?0=16:sa%?1=2
 1410 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1420 a%=1:o%=4
 1430 FOR i%=1 TO 4
 1440   b%=INSTR(host$+".",".",a%)
 1450   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1460   a%=b%+1:o%=o%+1
 1470 NEXT
 1480 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1490 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1500 PROCosw
 1510 IF blk%?3<>0 THEN PROCstop("cannot connect to "+STR$(port%)+", r=&"+STR$~blk%?3)
 1520 PROCw("connected to "+host$+":"+STR$(port%))
 1530 ENDPROC
 1540 :
 1550 DEF PROCclose
 1560 LOCAL i%
 1570 IF sock%<0 THEN ENDPROC
 1580 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1590 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1600 PROCosw
 1610 sock%=-1
 1620 ENDPROC
 1630 :
 1640 DEF PROCopen
 1650 rf%=OPENOUT(rf$)
 1660 ENDPROC
 1670 :
 1680 DEF PROCw(s$)
 1690 LOCAL i%
 1700 IF rf%=0 THEN ENDPROC
 1710 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1720 BPUT#rf%,13:BPUT#rf%,10
 1730 ENDPROC
 1740 :
 1750 DEF PROCshut
 1760 IF rf%<>0 THEN CLOSE#rf%
 1770 rf%=0
 1780 ENDPROC
 1790 :
 1800 DEF PROCstop(s$)
 1810 PROCw("fail="+s$)
 1820 PROCw("[end]")
 1830 PROCshut
 1840 PROCclose
 1850 PRINT "FBHOST: ";s$
 1860 END
 1870 :
 1880 DEF PROCerr
 1890 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 1900 PROCw("[end]")
 1910 PROCshut
 1920 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1930 REPORT:PRINT
 1940 ENDPROC
