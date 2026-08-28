   10 REM > FBASM - what does OSWORD &C0 cost with NO interpreter at all?
   20 REM
   30 REM   *EXEC FBASM   then RUN     on the HOST, co-processor OFF
   40 REM   socat TCP-LISTEN:2324,reuseaddr,fork EXEC:<repo>/tools/quiet.sh
   50 REM
   60 REM The one number left, and the one the ROM question turns on.
   70 REM
   80 REM   co-processor   Tube + module      = 3280us
   90 REM   host, BASIC    CALL + module      = 9900us
  100 REM   host, BASIC    the wrapper alone  = 35550us
  110 REM
  120 REM The module is common to both, so it must be under 3280us, which
  130 REM means most of the host's 9900 is BBC BASIC's CALL mechanism and
  140 REM not the module at all. That leaves the split unmeasured, and the
  150 REM two answers point opposite ways:
  160 REM
  170 REM   module ~0.5ms -> the Tube is 2.8ms of the 3.28, and a ROM doing
  180 REM   sixteen host-side recvs behind ONE crossing drains a burst
  190 REM   about three times faster. Worth building.
  200 REM
  210 REM   module ~3ms -> the Tube is nearly free, sixteen recvs cost the
  220 REM   same sixteen times, and a ROM gains nothing.
  230 REM
  240 REM BASIC cannot separate them: its overhead swamps the host and
  250 REM vanishes on the co-processor. So call OSWORD from assembler, with
  260 REM no interpreter in the loop - which is also exactly what a ROM
  270 REM would be doing, so this measures the thing itself.
  280 REM
  290 REM 200 calls per CALL, so the BASIC around it is a two hundredth of
  300 REM what is timed and cannot colour the answer.
  310 :
  320 host$="192.0.2.10":port%=2324
  330 rf$="RESASM"
  340 mnowait%=8
  350 outer%=5:inner%=200
  360 :
  370 rf%=0:sock%=-1
  380 ON ERROR PROCerr:END
  390 DIM blk% 31, sa% 31, rx% 127, cnt% 0, code% 200
  400 PROCopen
  410 PROCw("[fbasm1]")
  420 PROCw("run="+STR$(TIME))
  430 PROCconnect
  440 PROCassemble
  450 :
  460 REM The empty poll again, so it is the same measurement as the other
  470 REM two and the numbers can be put side by side.
  480 PROCrun
  490 :
  500 PROCw("[end]")
  510 PROCshut
  520 PROCclose
  530 PRINT "FBASM done - ";rf$;" is on the share."
  540 END
  550 :
 1000 REM inner% calls of OSWORD &C0, nothing else in the loop. The result
 1010 REM is discarded - we are timing the call, not reading the socket.
 1020 DEF PROCassemble
 1030 LOCAL opt%
 1040 FOR opt%=0 TO 2 STEP 2
 1050   P%=code%
 1060   [OPT opt%
 1070   .go
 1080   LDA #inner%
 1090   STA cnt%
 1100   .loop
 1110   LDA #&C0
 1120   LDX #(blk% AND 255)
 1130   LDY #(blk% DIV 256)
 1140   JSR &FFF1
 1150   DEC cnt%
 1160   BNE loop
 1170   RTS
 1180   ]
 1190 NEXT
 1200 ENDPROC
 1210 :
 1220 DEF PROCrun
 1230 LOCAL i%,t,c,n%
 1240 PROCsetup
 1250 t=TIME
 1260 FOR i%=1 TO outer%
 1270   CALL code%
 1280 NEXT
 1290 c=TIME-t
 1300 IF c<1 THEN c=1
 1310 n%=outer%*inner%
 1320 PROCw("asm_osword calls="+STR$(n%)+" cs="+STR$(c)+" us_per_call="+STR$(c*10000 DIV n%))
 1330 ENDPROC
 1340 :
 1350 REM Fill the block once. The assembler loop does not touch it, which
 1360 REM is the point: a ROM would set it up once and call repeatedly too.
 1370 DEF PROCsetup
 1380 LOCAL i%
 1390 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1400 blk%?0=20:blk%?1=8:blk%?2=&05
 1410 blk%!4=sock%:blk%!8=rx%:blk%!12=64:blk%!16=mnowait%
 1420 ENDPROC
 1430 :
 1440 DEF PROCosw
 1450 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1460 ENDPROC
 1470 :
 1480 DEF PROCconnect
 1490 LOCAL i%,a%,b%,o%
 1500 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1510 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1520 PROCosw
 1530 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1540 sock%=blk%!4
 1550 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1560 sa%?0=16:sa%?1=2
 1570 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1580 a%=1:o%=4
 1590 FOR i%=1 TO 4
 1600   b%=INSTR(host$+".",".",a%)
 1610   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1620   a%=b%+1:o%=o%+1
 1630 NEXT
 1640 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1650 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1660 PROCosw
 1670 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1680 PROCw("connected to "+host$+":"+STR$(port%))
 1690 ENDPROC
 1700 :
 1710 DEF PROCclose
 1720 LOCAL i%
 1730 IF sock%<0 THEN ENDPROC
 1740 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1750 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1760 PROCosw
 1770 sock%=-1
 1780 ENDPROC
 1790 :
 1800 DEF PROCopen
 1810 rf%=OPENOUT(rf$)
 1820 ENDPROC
 1830 :
 1840 DEF PROCw(s$)
 1850 LOCAL i%
 1860 IF rf%=0 THEN ENDPROC
 1870 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1880 BPUT#rf%,13:BPUT#rf%,10
 1890 ENDPROC
 1900 :
 1910 DEF PROCshut
 1920 IF rf%<>0 THEN CLOSE#rf%
 1930 rf%=0
 1940 ENDPROC
 1950 :
 1960 DEF PROCstop(s$)
 1970 PROCw("fail="+s$)
 1980 PROCw("[end]")
 1990 PROCshut
 2000 PROCclose
 2010 PRINT "FBASM: ";s$
 2020 END
 2030 :
 2040 DEF PROCerr
 2050 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2060 PROCw("[end]")
 2070 PROCshut
 2080 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2090 REPORT:PRINT
 2100 ENDPROC
