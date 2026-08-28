   10 REM > FBSIZE - what is the largest read the module reliably satisfies?
   20 REM
   30 REM   CHAIN "FBSIZE"     copro 15, *ARMBASIC, tube on
   40 REM
   50 REM Measured on hardware: a peek reports N bytes available, the recv for
   60 REM exactly those N bytes then answers a non-zero +3 - and the bytes are
   70 REM gone. 21 times in one session, the last of them at N=88. recv(1)
   80 REM never fails, which is why one byte per read loses nothing and runs
   90 REM at 72 bytes/sec.
  100 REM
  110 REM So there is a size at which recv stops being reliable, and finding it
  120 REM is worth a probe: it is the difference between a terminal that is
  130 REM correct at 72 bytes/sec and one that is correct at a useful speed.
  140 REM
  150 REM For each size it does N cycles of peek-then-read and counts how many
  160 REM reads the module refused after its own peek said the bytes were
  170 REM there. A size with no refusals in a hundred tries is one the client
  180 REM can use.
  190 REM
  200 REM Needs a listener with a lot to say:
  210 REM
  220 REM   socat TCP-LISTEN:2323,reuseaddr,fork SYSTEM:'yes ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 | head -c 300000'
  230 :
  240 host$="192.0.2.10":port%=2323
  250 rf$="RESSIZE"
  260 mpeek%=1:mnowait%=8
  270 tries%=100
  280 :
  290 rf%=0:sock%=-1
  300 ON ERROR PROCerr:END
  310 DIM blk% 31, sa% 31, rx% 255
  320 PROCopen
  330 PROCw("[fbsize1]")
  340 PROCw("run="+STR$(TIME))
  350 PROCconnect
  360 PROCw("size  asked   ok   refused   bytes   worst")
  370 sz%=1
  380 FOR p%=0 TO 7
  390   PROCtry(sz%)
  400   sz%=sz%*2
  410 NEXT
  420 PROCw("[end]")
  430 PROCshut
  440 PROCclose
  450 VDU 26:CLS
  460 PRINT "FBSIZE done - ";rf$;" is on the share."
  470 END
  480 :
  490 REM One size. Peek up to sz%, then read exactly what the peek reported,
  500 REM and count the reads the module refuses after saying they were there.
  510 REM Flat, because ELSE binds to the FIRST IF on the line in BBC BASIC.
  520 REM Written as one line with a nested IF it counted a refusal every time
  530 REM there was simply nothing to read, which would have made every size
  540 REM look broken. baslint caught it - the rule came out of this project
  550 REM three hours ago.
 1000 DEF PROCtry(sz%)
 1010 LOCAL i%,a%
 1020 ok%=0:no%=0:by%=0:worst%=0
 1030 FOR i%=1 TO tries%
 1040   a%=FNpeek(sz%)
 1050   IF a%<1 THEN PROCidle
 1060   IF a%<1 THEN a%=FNpeek(sz%)
 1070   IF a%>0 THEN PROCone(a%)
 1080 NEXT
 1090 PROCw(FNpad(STR$(sz%),6)+FNpad(STR$(ok%+no%),7)+FNpad(STR$(ok%),6)+FNpad(STR$(no%),9)+FNpad(STR$(by%),8)+STR$(worst%))
 1100 ENDPROC
 1110 :
 1120 REM One peek-then-read pair. The counters are global because BASIC has
 1130 REM no way to hand several back from a procedure.
 1140 DEF PROCone(a%)
 1150 LOCAL g%
 1160 g%=FNtake(a%)
 1170 IF g%>0 THEN ok%=ok%+1:by%=by%+g%:ENDPROC
 1180 no%=no%+1
 1190 IF a%>worst% THEN worst%=a%
 1200 ENDPROC
 1210 :
 1220 DEF FNpeek(n%)
 1230 LOCAL i%
 1240 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1250 blk%?0=20:blk%?1=8:blk%?2=&05
 1260 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mpeek%+mnowait%
 1270 SYS "OS_Word",&C0,blk%
 1280 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1290 IF blk%?3<>0 THEN =0
 1300 =blk%!4
 1310 :
 1320 DEF FNtake(n%)
 1330 LOCAL i%
 1340 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1350 blk%?0=20:blk%?1=8:blk%?2=&05
 1360 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mnowait%
 1370 SYS "OS_Word",&C0,blk%
 1380 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1390 IF blk%?3<>0 THEN =0
 1400 =blk%!4
 1410 :
 1420 REM Give the far end a moment to put something in the pipe.
 1430 DEF PROCidle
 1440 LOCAL t
 1450 t=TIME
 1460 REPEAT UNTIL TIME-t>5
 1470 ENDPROC
 1480 :
 1490 DEF FNpad(s$,n%)
 1500 IF LEN(s$)>=n% THEN =s$+" "
 1510 =s$+STRING$(n%-LEN(s$)," ")
 1520 :
 1530 DEF PROCconnect
 1540 LOCAL i%,a%,b%,o%
 1550 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1560 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1570 SYS "OS_Word",&C0,blk%
 1580 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1590 sock%=blk%!4
 1600 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1610 sa%?0=16:sa%?1=2
 1620 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1630 a%=1:o%=4
 1640 FOR i%=1 TO 4
 1650   b%=INSTR(host$+".",".",a%)
 1660   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1670   a%=b%+1:o%=o%+1
 1680 NEXT
 1690 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1700 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1710 SYS "OS_Word",&C0,blk%
 1720 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1730 PROCw("connected to "+host$+":"+STR$(port%))
 1740 ENDPROC
 1750 :
 1760 DEF PROCclose
 1770 LOCAL i%
 1780 IF sock%<0 THEN ENDPROC
 1790 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1800 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1810 SYS "OS_Word",&C0,blk%
 1820 sock%=-1
 1830 ENDPROC
 1840 :
 1850 DEF PROCopen
 1860 rf%=OPENOUT(rf$)
 1870 ENDPROC
 1880 :
 1890 DEF PROCw(s$)
 1900 LOCAL i%
 1910 IF rf%=0 THEN ENDPROC
 1920 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1930 BPUT#rf%,13:BPUT#rf%,10
 1940 ENDPROC
 1950 :
 1960 DEF PROCshut
 1970 IF rf%<>0 THEN CLOSE#rf%
 1980 rf%=0
 1990 ENDPROC
 2000 :
 2010 DEF PROCstop(s$)
 2020 PROCw("fail="+s$)
 2030 PROCw("[end]")
 2040 PROCshut
 2050 PROCclose
 2060 PRINT "FBSIZE: ";s$
 2070 END
 2080 :
 2090 DEF PROCerr
 2100 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2110 PROCw("[end]")
 2120 PROCshut
 2130 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2140 REPORT:PRINT
 2150 ENDPROC
