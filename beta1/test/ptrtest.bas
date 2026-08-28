   10 REM > PTRTEST - do OSWORD &C0 buffer pointers cross the Tube on copro 15?
   20 REM
   30 REM specification.md 2.4 has had this open since copro 15 was chosen. 5.5c
   40 REM proved pointers cross on a 6502 core, where the pointer in the control
   50 REM block is a 16-bit address the host already understands. On native ARM
   60 REM it is a 32-bit ARM address and nobody has checked.
   70 REM
   80 REM COPRO 15 ONLY:  *FX 151,230,15  then CTRL-BREAK  then *ARMBASIC
   90 REM
  100 REM Needs a listener that says something on connect. On the Linux box:
  110 REM
  120 REM   socat TCP-LISTEN:6502,reuseaddr,fork SYSTEM:'echo PTRTEST-MARKER-42; cat'
  130 REM
  140 REM Two things this does that the offline probe could not:
  150 REM
  160 REM   The receive buffer is POISONED with &55 before the call, so "the
  170 REM   module wrote nothing" is distinguishable from "the module wrote
  180 REM   zeros". The offline probe read a 0 back and could not tell.
  190 REM
  200 REM   The receive buffer is placed ABOVE &10000, so its address does not
  210 REM   fit in 16 bits. If bytes arrive there, a 32-bit ARM pointer was
  220 REM   honoured - it cannot be a truncated host write landing by luck.
  230 :
  240 ip$="192.0.2.10":pt%=6502
  250 rf$="RESPTR"
  260 :
  270 rf%=0:k%=-1
  280 ON ERROR PROCerr:END
  290 PROCopen
  300 PROCw("[ptrtest1]")
  310 PROCw("run="+STR$(TIME))
  320 :
  330 REM Push the receive buffer past 64K, then nudge it until its low 16
  340 REM bits land in &8000-&BFFF. If the pointer is NOT honoured the module
  350 REM writes to the host at the truncated address, and that window is
  360 REM sideways ROM, where the write does nothing. Anywhere lower is MOS
  370 REM workspace and a failed test would present as a hung machine.
  380 DIM pad% &10000
  390 DIM b% 31, a% 31, t% 255
  400 DIM r% 255
  410 n%=0
  420 REPEAT
  430   lo%=r% AND &FFFF
  440   IF lo%<&8000 OR lo%>=&C000 THEN DIM junk% 511:DIM r% 255
  450   n%=n%+1
  460 UNTIL (lo%>=&8000 AND lo%<&C000) OR n%>400
  470 :
  480 PRINT "PTRTEST - copro 15"
  490 PROCw("page=&"+STR$~PAGE+" himem=&"+STR$~HIMEM)
  500 PROCw("block=&"+STR$~b%)
  510 PROCw("recvbuf=&"+STR$~r%+" low16=&"+STR$~(r% AND &FFFF))
  520 PRINT "recv buffer at &";~r%
  530 IF r%<&10000 THEN PROCw("fail=recv buffer did not clear 64K"):PROCstop("buffer below 64K")
  540 IF (r% AND &FFFF)<&8000 OR (r% AND &FFFF)>=&C000 THEN PROCw("warn=low16 outside the safe window")
  550 :
  560 REM ---- 1. presence. No pointers at all. ----
  570 PROCzero:b%?0=8:b%?1=8:b%?2=&10:b%!4=-1
  580 PROCosw
  590 PROCsay("presence","+2="+STR$~b%?2+" +3="+STR$~b%?3)
  600 IF b%?2<>0 THEN PROCw("fail=OSWORD &C0 unanswered"):PROCstop("nothing claimed OSWORD &C0")
  610 :
  620 REM ---- 2. Socket_Creat. Still no pointers. Command byte is 0, so a
  630 REM zeroed +2 proves nothing and a sentinel at +4 does the work. ----
  640 PROCzero:b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  650 PROCosw
  660 k%=b%!4
  670 PROCsay("creat","+3="+STR$~b%?3+" sock="+STR$(k%))
  680 IF b%?3<>0 OR k%<0 THEN PROCw("fail=creat"):PROCstop("Socket_Creat failed")
  690 :
  700 REM ---- 3. Socket_Connect. THE POINTER GOES OUT: a% holds a 16-byte
  710 REM sockaddr and only the module reading ARM memory can connect. ----
  720 PROCaddr
  730 PROCw("sockaddr=&"+STR$~a%)
  740 PROCzero:b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16
  750 PROCosw
  760 PROCsay("connect","+2="+STR$~b%?2+" +3="+STR$~b%?3)
  770 IF b%?3<>0 THEN PROCw("ptr_out=NO"):PROCw("[end]"):PROCshut:PRINT "connect failed - pointers do NOT cross outward":PROCclose:END
  780 PROCw("ptr_out=YES")
  790 PRINT "connect OK - the module read ARM memory"
  800 :
  810 REM ---- 4. Socket_Send. A second pointer outward, this time with data
  820 REM the far end can be seen to receive. ----
  830 len%=FNput("PTRTEST speaking from copro 15")
  840 PROCzero:b%?0=20:b%?1=8:b%?2=8:b%!4=k%:b%!8=t%:b%!12=len%
  850 PROCosw
  860 PROCsay("send","+2="+STR$~b%?2+" +3="+STR$~b%?3+" sent="+STR$(b%!4)+" of "+STR$(len%))
  870 :
  880 REM ---- 5. Socket_Recv. THE POINTER COMES BACK. This is the direction
  890 REM that failed offline and the reason the test exists. ----
  900 PROCpoison
  910 PROCw("poison=&55 x 256")
  920 T=TIME:got%=0
  930 REPEAT
  940   PROCzero:b%?0=20:b%?1=8:b%?2=5:b%!4=k%:b%!8=r%:b%!12=1:b%!16=8
  950   PROCosw
  960   IF b%?2<>0 THEN PROCw("fail=recv unclaimed"):got%=-1
  970   IF b%!4=1 AND got%>=0 THEN got%=got%+1:T=TIME
  980 UNTIL (TIME-T)>500 OR got%>=16 OR got%<0
  990 PROCsay("recv","reported="+STR$(got%)+" bytes")
 1000 PROCw("buf="+FNhex(16))
 1010 PROCw("txt="+FNtxt(16))
 1020 :
 1030 REM Untouched poison means the module never wrote to ARM memory, however
 1040 REM many bytes it claimed to deliver. That is the whole answer. Counted
 1050 REM over sixteen bytes rather than one, because a far end that happened
 1060 REM to send &55 would otherwise read as a failure.
 1070 ch%=0
 1080 FOR i%=0 TO 15:IF r%?i%<>&55 THEN ch%=ch%+1
 1090 NEXT
 1100 PROCw("changed="+STR$(ch%)+" of 16")
 1110 IF got%<1 THEN PROCw("ptr_in=NODATA")
 1120 IF got%>0 AND ch%=0 THEN PROCw("ptr_in=NO")
 1130 IF got%>0 AND ch%>0 THEN PROCw("ptr_in=YES")
 1140 IF got%>0 AND ch%>0 THEN PRINT "*** POINTERS CROSS THE TUBE ON COPRO 15 ***"
 1150 IF got%>0 AND ch%=0 THEN PRINT "recv claimed data but ARM memory is untouched"
 1160 :
 1170 PROCclose
 1180 PROCw("[end]")
 1190 PROCshut
 1200 PRINT "PTRTEST done - RESPTR is on the share"
 1210 END
 1220 :
 1230 DEF PROCsay(n$,s$)
 1240 PRINT n$;"  ";s$
 1250 PROCw(n$+" "+s$)
 1260 ENDPROC
 1270 :
 1280 DEF FNput(s$)
 1290 LOCAL i%
 1300 FOR i%=1 TO LEN(s$):t%?(i%-1)=ASC(MID$(s$,i%,1)):NEXT
 1310 t%?LEN(s$)=13:t%?(LEN(s$)+1)=10
 1320 =LEN(s$)+2
 1330 :
 1340 DEF PROCpoison
 1350 LOCAL i%
 1360 FOR i%=0 TO 255:r%?i%=&55:NEXT
 1370 ENDPROC
 1380 :
 1390 DEF FNhex(n%)
 1400 LOCAL i%,s$
 1410 s$=""
 1420 FOR i%=0 TO n%-1:s$=s$+RIGHT$("0"+STR$~(r%?i%),2)+" ":NEXT
 1430 =s$
 1440 :
 1450 DEF FNtxt(n%)
 1460 LOCAL i%,s$,c%
 1470 s$=""
 1480 FOR i%=0 TO n%-1
 1490   c%=r%?i%
 1500   IF c%<32 OR c%>126 THEN c%=46
 1510   s$=s$+CHR$(c%)
 1520 NEXT
 1530 =s$
 1540 :
 1550 REM sockaddr_in - confirmed layout, netprogapi.pdf
 1560 DEF PROCaddr
 1570 LOCAL i%,p%,q%,o%
 1580 FOR i%=0 TO 15:a%?i%=0:NEXT
 1590 a%?0=16:a%?1=2
 1600 a%?2=pt% DIV 256:a%?3=pt% MOD 256
 1610 p%=1:o%=4
 1620 FOR i%=1 TO 4
 1630   q%=INSTR(ip$+".",".",p%)
 1640   a%?o%=VAL(MID$(ip$,p%,q%-p%))
 1650   p%=q%+1:o%=o%+1
 1660 NEXT
 1670 ENDPROC
 1680 :
 1690 DEF PROCclose
 1700 IF k%<0 THEN ENDPROC
 1710 PROCzero:b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
 1720 PROCosw
 1730 k%=-1
 1740 ENDPROC
 1750 :
 1760 REM +3 MUST be zero on entry - netprogapi.pdf
 1770 DEF PROCzero
 1780 LOCAL i%
 1790 FOR i%=0 TO 27:b%?i%=0:NEXT
 1800 ENDPROC
 1810 :
 1820 REM There is no CALL &FFF1 on ARM. SYS "OS_Word" takes the reason code
 1830 REM in R0 and the control block in R1.
 1840 DEF PROCosw
 1850 SYS "OS_Word",&C0,b%
 1860 ENDPROC
 1870 :
 1880 DEF PROCopen
 1890 rf%=OPENOUT(rf$)
 1900 ENDPROC
 1910 :
 1920 DEF PROCw(s$)
 1930 LOCAL i%
 1940 IF rf%=0 THEN ENDPROC
 1950 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1960 BPUT#rf%,13:BPUT#rf%,10
 1970 ENDPROC
 1980 :
 1990 DEF PROCshut
 2000 IF rf%<>0 THEN CLOSE#rf%
 2010 rf%=0
 2020 ENDPROC
 2030 :
 2040 DEF PROCstop(s$)
 2050 PROCw("[end]")
 2060 PROCshut
 2070 PRINT "PTRTEST stopped: ";s$
 2080 END
 2090 :
 2100 DEF PROCerr
 2110 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2120 REPORT:PRINT
 2130 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2140 PROCw("[end]")
 2150 PROCshut
 2160 ENDPROC
