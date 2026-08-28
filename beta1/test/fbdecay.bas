   10 REM > FBDECAY - does the flow collapse, and do the strategies differ
   20 REM              once drift is controlled for?
   30 REM
   40 REM   CHAIN "FBDECAY"    copro 15, *ARMBASIC, tube on
   50 REM   socat TCP-LISTEN:2323,reuseaddr,fork EXEC:<repo>/tools/feed.sh
   60 REM
   70 REM FBWAY's drift check fired. The same strategy scored 1082 bytes/sec
   80 REM and then 241 on its two runs, a 4.5x swing, so nothing in that
   90 REM table could be compared with anything else in it.
  100 REM
  110 REM But the pattern of the failure is itself the finding. The FIRST
  120 REM window ran fast and everything after it crawled - one strategy got
  130 REM nothing whatever out of 861 calls. That is not a strategy
  140 REM difference, that is the connection degrading, and it matches what
  150 REM the user reported from the other end: everything goes slow once a
  160 REM flooding top has overloaded the receive buffer.
  170 REM
  180 REM One thing survived the drift and kills an old assumption outright:
  190 REM way 4 pulled 1024 bytes in a SINGLE call. There is no 64 cap, no
  200 REM 128 cap and no Tube control-block cap. When the module holds a big
  210 REM block it hands over all of it at once.
  220 REM
  230 REM PART 1 measures the shape of the collapse: one strategy, twenty
  240 REM one-second buckets, on a fresh connection. If bucket 1 is fast and
  250 REM bucket 20 is a crawl, the buffer overflows and recovery is slow,
  260 REM and THAT is the bottleneck rather than anything about read size.
  270 REM
  280 REM PART 2 compares the four strategies with drift controlled for, by
  290 REM INTERLEAVING them in quarter-second slices and cycling forty times
  300 REM instead of giving each one long block. Whatever the far end does,
  310 REM it now does it to all four roughly equally.
  320 :
  330 host$="192.0.2.10":port%=2323
  340 rf$="RESDECAY"
  350 mpeek%=1:mnowait%=8
  360 top%=1024
  370 buck%=100:nbuck%=20
  380 slice%=25:rounds%=40
  390 :
  400 rf%=0:sock%=-1:err%=0:eof%=FALSE
  410 ON ERROR PROCerr:END
  420 REM Sixteen bytes each, not four: PROCtot reads FOUR words per block
  425 REM (calls, hits, bytes, biggest) and PROCzero writes all four. DIM
  426 REM w1% 3 gave four bytes, so zeroing walked through w2, w3, w4 and
  427 REM into BASIC own variables - which is why it died with Mistake in
  428 REM the middle of the loop rather than at the DIM.
  429 DIM blk% 31, sa% 31, rx% top%, w1% 15, w2% 15, w3% 15, w4% 15
  430 PROCopen
  440 PROCw("[fbdecay1]")
  450 PROCw("run="+STR$(TIME))
  460 PROCconnect
  470 :
  480 PROCw("[part1] fresh connection, bare read of 64, one second a bucket")
  490 PROCw("bucket  calls  hits  bytes  biggest")
  500 FOR b%=1 TO nbuck%
  510   IF NOT eof% THEN PROCbucket(b%)
  520 NEXT
  530 :
  540 REM A new connection, so part 2 does not start from a wrecked one.
  550 PROCw("[part2] interleaved slices, "+STR$(rounds%)+" rounds of "+STR$(slice%)+"cs")
  560 PROCclose
  570 eof%=FALSE
  580 PROCconnect
  590 PROCzero
  600 FOR r%=1 TO rounds%
  610   IF NOT eof% THEN PROCslice(1,w1%)
  620   IF NOT eof% THEN PROCslice(2,w2%)
  630   IF NOT eof% THEN PROCslice(3,w3%)
  640   IF NOT eof% THEN PROCslice(4,w4%)
  650 NEXT
  660 PROCw("way  calls  hits  bytes   biggest")
  670 PROCtot(1,w1%)
  680 PROCtot(2,w2%)
  690 PROCtot(3,w3%)
  700 PROCtot(4,w4%)
  710 :
  720 PROCw("eof="+STR$(eof%))
  730 PROCw("[end]")
  740 PROCshut
  750 PROCclose
  760 PRINT "FBDECAY done - ";rf$;" is on the share."
  770 END
  780 :
 1000 DEF PROCbucket(b%)
 1010 LOCAL t
 1020 ca%=0:hi%=0:by%=0:big%=0
 1030 t=TIME
 1040 REPEAT
 1050   PROCbare(64)
 1060 UNTIL TIME-t>=buck% OR eof%
 1070 PROCw(FNpad(STR$(b%),8)+FNpad(STR$(ca%),7)+FNpad(STR$(hi%),6)+FNpad(STR$(by%),7)+STR$(big%))
 1080 ENDPROC
 1090 :
 1100 REM One slice of one strategy. Totals accumulate into that way's own
 1110 REM four-word block, so the rounds add up across the whole run.
 1120 DEF PROCslice(w%,p%)
 1130 LOCAL t
 1140 ca%=0:hi%=0:by%=0:big%=0
 1150 t=TIME
 1160 REPEAT
 1170   IF w%=1 THEN PROCbare(64)
 1180   IF w%=2 THEN PROCbare(32)
 1190   IF w%=3 THEN PROCpeeked(64)
 1200   IF w%=4 THEN PROCpeeked(top%)
 1210 UNTIL TIME-t>=slice% OR eof%
 1220 p%!0=p%!0+ca%:p%!4=p%!4+hi%:p%!8=p%!8+by%
 1230 IF big%>p%!12 THEN p%!12=big%
 1240 ENDPROC
 1250 :
 1260 DEF PROCtot(w%,p%)
 1270 PROCw(FNpad(STR$(w%),5)+FNpad(STR$(p%!0),7)+FNpad(STR$(p%!4),6)+FNpad(STR$(p%!8),8)+STR$(p%!12))
 1280 ENDPROC
 1290 :
 1300 DEF PROCzero
 1310 LOCAL i%
 1320 FOR i%=0 TO 12 STEP 4
 1330   w1%!i%=0:w2%!i%=0:w3%!i%=0:w4%!i%=0
 1340 NEXT
 1350 ENDPROC
 1360 :
 1370 DEF PROCbare(n%)
 1380 LOCAL g%
 1390 g%=FNtake(n%,0)
 1400 IF g%>0 THEN PROCscore(g%)
 1410 IF g%=0 THEN eof%=TRUE
 1420 ENDPROC
 1430 :
 1440 DEF PROCpeeked(n%)
 1450 LOCAL a%,g%
 1460 a%=FNtake(n%,mpeek%)
 1470 IF a%=0 THEN eof%=TRUE
 1480 IF a%<1 THEN ENDPROC
 1490 IF a%>n% THEN a%=n%
 1500 g%=FNtake(a%,0)
 1510 IF g%>0 THEN PROCscore(g%)
 1520 IF g%=0 THEN eof%=TRUE
 1530 ENDPROC
 1540 :
 1550 DEF PROCscore(g%)
 1560 hi%=hi%+1:by%=by%+g%
 1570 IF g%>big% THEN big%=g%
 1580 ENDPROC
 1590 :
 1600 DEF FNtake(n%,f%)
 1610 LOCAL i%
 1620 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1630 blk%?0=20:blk%?1=8:blk%?2=&05
 1640 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=f%+mnowait%
 1650 ca%=ca%+1
 1660 PROCosw
 1670 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1680 err%=blk%?3
 1690 IF err%<>0 THEN =-2
 1700 =blk%!4
 1710 :
 1720 DEF PROCosw
 1730 SYS "OS_Word",&C0,blk%
 1740 ENDPROC
 1750 :
 1760 DEF FNpad(s$,n%)
 1770 IF LEN(s$)>=n% THEN =s$+" "
 1780 =s$+STRING$(n%-LEN(s$)," ")
 1790 :
 1800 DEF PROCconnect
 1810 LOCAL i%,a%,b%,o%
 1820 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1830 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1840 PROCosw
 1850 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1860 sock%=blk%!4
 1870 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1880 sa%?0=16:sa%?1=2
 1890 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1900 a%=1:o%=4
 1910 FOR i%=1 TO 4
 1920   b%=INSTR(host$+".",".",a%)
 1930   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1940   a%=b%+1:o%=o%+1
 1950 NEXT
 1960 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1970 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1980 PROCosw
 1990 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 2000 PROCw("connected to "+host$+":"+STR$(port%))
 2010 ENDPROC
 2020 :
 2030 DEF PROCclose
 2040 LOCAL i%
 2050 IF sock%<0 THEN ENDPROC
 2060 FOR i%=0 TO 27:blk%?i%=0:NEXT
 2070 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 2080 PROCosw
 2090 sock%=-1
 2100 ENDPROC
 2110 :
 2120 DEF PROCopen
 2130 rf%=OPENOUT(rf$)
 2140 ENDPROC
 2150 :
 2160 DEF PROCw(s$)
 2170 LOCAL i%
 2180 IF rf%=0 THEN ENDPROC
 2190 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 2200 BPUT#rf%,13:BPUT#rf%,10
 2210 ENDPROC
 2220 :
 2230 DEF PROCshut
 2240 IF rf%<>0 THEN CLOSE#rf%
 2250 rf%=0
 2260 ENDPROC
 2270 :
 2280 DEF PROCstop(s$)
 2290 PROCw("fail="+s$)
 2300 PROCw("[end]")
 2310 PROCshut
 2320 PROCclose
 2330 PRINT "FBDECAY: ";s$
 2340 END
 2350 :
 2360 DEF PROCerr
 2370 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2380 PROCw("[end]")
 2390 PROCshut
 2400 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2410 REPORT:PRINT
 2420 ENDPROC
