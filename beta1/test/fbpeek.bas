   10 REM > FBPEEK - is MSG_PEEK usable, and is it non-destructive?
   20 REM
   30 REM   CHAIN "FBPEEK"     copro 15, *ARMBASIC, tube on
   40 REM
   50 REM Hardware measured that asking Socket_Recv for more bytes than the
   60 REM module has loses the difference - 250 bytes in one session - so the
   70 REM client is down to one byte per read, which 5.5c measured at 72
   80 REM bytes/sec against 3082 for the adaptive ramp.
   90 REM
  100 REM MSG_PEEK (flag 1) is listed as supported in netprogapi.pdf. If it is
  110 REM non-destructive, the read can be sized exactly instead of guessed:
  120 REM peek to find out how much is there, then ask for precisely that, and
  130 REM nothing is ever over-asked. That is the whole terminal's throughput.
  140 REM
  150 REM Three questions, in order, each meaningless if the one before failed:
  160 REM
  170 REM   1 does a peek return data at all
  180 REM   2 does peeking the SAME bytes twice give the same answer - if the
  190 REM     second peek returns different bytes it consumed, and the flag is
  200 REM     useless for sizing
  210 REM   3 does an OVER-ASKED peek report what is there, or &1E? If it
  220 REM     reports, sizing is one call. If &1E, it takes a few halvings -
  230 REM     still far better than one byte at a time, but only if the failed
  240 REM     peeks do not consume either, which 2 has to be re-checked for.
  250 REM
  260 REM Needs a listener that sends a known burst and then holds:
  270 REM
  280 REM   socat TCP-LISTEN:2323,reuseaddr,fork SYSTEM:'printf ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789; sleep 60'
  290 :
  300 host$="192.0.2.10":port%=2323
  310 rf$="RESPEEK"
  320 PEEK%=1:DONTWAIT%=8
  330 :
  340 rf%=0:sock%=-1
  350 ON ERROR PROCerr:END
  360 DIM blk% 31, sa% 31, b1% 255, b2% 255
  370 PROCopen
  380 PROCw("[fbpeek1]")
  390 PROCw("run="+STR$(TIME))
  400 PROCconnect
  410 PROCwaitdata
  420 :
  430 PROCw("--- 1. does a peek return data")
  440 n1%=FNrecv(b1%,8,PEEK%+DONTWAIT%)
  450 PROCw("peek8_a=+3="+STR$~res%+" n="+STR$(n1%)+" ["+FNtxt(b1%,n1%)+"]")
  460 IF n1%<1 THEN PROCw("peek=NO"):PROCdone
  470 PROCw("peek=YES")
  480 :
  490 PROCw("--- 2. is it non-destructive")
  500 n2%=FNrecv(b2%,8,PEEK%+DONTWAIT%)
  510 PROCw("peek8_b=+3="+STR$~res%+" n="+STR$(n2%)+" ["+FNtxt(b2%,n2%)+"]")
  520 IF n1%=n2% AND FNsame(n1%) THEN PROCw("peek_same=YES") ELSE PROCw("peek_same=NO")
  530 :
  540 PROCw("--- 3. what does an over-asked peek do")
  550 n3%=FNrecv(b2%,200,PEEK%+DONTWAIT%)
  560 PROCw("peek200=+3="+STR$~res%+" n="+STR$(n3%))
  570 IF res%=0 AND n3%>0 THEN PROCw("oversize_peek=REPORTS") ELSE PROCw("oversize_peek=REFUSES")
  580 :
  590 PROCw("--- 4. does the real read still see everything")
  600 n4%=FNrecv(b2%,8,DONTWAIT%)
  610 PROCw("recv8=+3="+STR$~res%+" n="+STR$(n4%)+" ["+FNtxt(b2%,n4%)+"]")
  620 IF n4%=n1% AND FNsame(n4%) THEN PROCw("peek_kept_data=YES") ELSE PROCw("peek_kept_data=NO")
  630 :
  640 n5%=FNrecv(b2%,8,DONTWAIT%)
  650 PROCw("recv8_next=+3="+STR$~res%+" n="+STR$(n5%)+" ["+FNtxt(b2%,n5%)+"]")
  660 PROCdone
  670 :
 1000 DEF PROCdone
 1010 PROCw("[end]")
 1020 PROCshut
 1030 PROCclose
 1040 VDU 26:CLS
 1050 PRINT "FBPEEK done - ";rf$;" is on the share."
 1060 END
 1070 :
 1080 REM One recv, with whatever flags, into whatever buffer. res% carries
 1090 REM +3 back out because &1E is a result and not an error.
 1100 DEF FNrecv(buf%,want%,fl%)
 1110 LOCAL i%
 1120 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1130 blk%?0=20:blk%?1=8:blk%?2=&05
 1140 blk%!4=sock%:blk%!8=buf%:blk%!12=want%:blk%!16=fl%
 1150 SYS "OS_Word",&C0,blk%
 1160 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1170 res%=blk%?3
 1180 IF res%<>0 THEN =0
 1190 =blk%!4
 1200 :
 1210 DEF FNsame(n%)
 1220 LOCAL i%,ok%
 1230 ok%=TRUE
 1240 FOR i%=0 TO n%-1
 1250   IF b1%?i%<>b2%?i% THEN ok%=FALSE
 1260 NEXT
 1270 =ok%
 1280 :
 1290 DEF FNtxt(p%,n%)
 1300 LOCAL i%,s$,c%
 1310 s$=""
 1320 IF n%<1 THEN =""
 1330 FOR i%=0 TO n%-1
 1340   c%=p%?i%
 1350   IF c%<32 OR c%>126 THEN c%=46
 1360   s$=s$+CHR$(c%)
 1370 NEXT
 1380 =s$
 1390 :
 1400 REM Poll a ONE byte peek until something arrives. One byte is the only
 1410 REM size the module can always satisfy, so this cannot itself lose data
 1420 REM even if peek turns out to be destructive.
 1430 DEF PROCwaitdata
 1440 LOCAL t,n%
 1450 t=TIME
 1460 REPEAT
 1470   n%=FNrecv(b2%,1,PEEK%+DONTWAIT%)
 1480 UNTIL n%>0 OR TIME-t>1500
 1490 IF n%<1 THEN PROCw("fail=no data arrived in 15 seconds"):PROCdone
 1500 ENDPROC
 1510 :
 1520 DEF PROCconnect
 1530 LOCAL i%,a%,b%,o%
 1540 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1550 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1560 SYS "OS_Word",&C0,blk%
 1570 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1580 sock%=blk%!4
 1590 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1600 sa%?0=16:sa%?1=2
 1610 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1620 a%=1:o%=4
 1630 FOR i%=1 TO 4
 1640   b%=INSTR(host$+".",".",a%)
 1650   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1660   a%=b%+1:o%=o%+1
 1670 NEXT
 1680 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1690 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1700 SYS "OS_Word",&C0,blk%
 1710 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1720 PROCw("connected to "+host$+":"+STR$(port%))
 1730 ENDPROC
 1740 :
 1750 DEF PROCclose
 1760 IF sock%<0 THEN ENDPROC
 1770 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1780 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1790 SYS "OS_Word",&C0,blk%
 1800 sock%=-1
 1810 ENDPROC
 1820 :
 1830 DEF PROCopen
 1840 rf%=OPENOUT(rf$)
 1850 ENDPROC
 1860 :
 1870 DEF PROCw(s$)
 1880 LOCAL i%
 1890 IF rf%=0 THEN ENDPROC
 1900 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1910 BPUT#rf%,13:BPUT#rf%,10
 1920 ENDPROC
 1930 :
 1940 DEF PROCshut
 1950 IF rf%<>0 THEN CLOSE#rf%
 1960 rf%=0
 1970 ENDPROC
 1980 :
 1990 DEF PROCstop(s$)
 2000 PROCw("fail="+s$)
 2010 PROCw("[end]")
 2020 PROCshut
 2030 PROCclose
 2040 PRINT "FBPEEK: ";s$
 2050 END
 2060 :
 2070 DEF PROCerr
 2080 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2090 PROCw("[end]")
 2100 PROCshut
 2110 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2120 REPORT:PRINT
 2130 ENDPROC
