   10 REM > NETTEST
   20 REM Step 0a - OSWORD &C0 probe, host only.
   30 REM Sprow Master 10/100 Ethernet module.
   40 REM Runs on the BBC Master HOST. No Tube, no ROM involved.
   50 REM
   60 REM This is a PROBE, not a client. The sockaddr layout, the
   70 REM AF_/SOCK_ constants and the location of the return value
   80 REM are NOT documented - see specification.md section 4.
   90 REM Every call dumps the control block before and after so the
  100 REM real conventions can be read off the screen.
  110 :
  120 ON ERROR PROCerr:END
  130 MODE 3
  140 :
  150 REM ---------------- configuration ----------------
  160 ip$="192.0.2.50"
  170 port%=2323
  180 REM sockaddr flavour: TRUE = BSD4.4 (leading length byte)
  190 REM                  FALSE = BSD4.3 (16-bit family, no length)
  200 sa44%=TRUE
  210 REM constants - ASSUMED, not verified
  220 AFINET%=2
  230 SOCKSTREAM%=1
  240 FIONBIO%=&8004667E
  250 :
  260 DIM blk% 31
  270 DIM sa% 31
  280 DIM buf% 255
  290 :
  300 PRINT "NETTEST - OSWORD &C0 probe"
  310 PRINT "Target ";ip$;":";port%
  320 PRINT STRING$(70,"-")
  330 :
  340 PROCcreat
  345 IF noresp% THEN PROCnomodule:END
  350 IF sock%<0 THEN PRINT "Stopping - Creat failed.":END
  360 PROCnonblock
  370 PROCconnect
  380 IF blk%?3<>0 THEN PRINT "Stopping - Connect failed.":PROCclose:END
  390 PROCsend(CHR$13+CHR$10)
  400 PROCrecvloop
  410 PROCclose
  420 PRINT "Done."
  430 END
  440 :
  442 DEF PROCnomodule
  444 PRINT
  446 PRINT "The control block came back untouched, so no ROM"
  448 PRINT "claimed OSWORD &C0. Either the Sprow module is not"
  450 PRINT "fitted/initialised, or this is an emulator - no BBC"
  452 PRINT "emulator implements the module. Step 0a needs real"
  454 PRINT "hardware."
  456 ENDPROC
  458 :
  462 REM ================ socket calls ================
  464 :
  470 DEF PROCcreat
  480 PRINT "--- Socket_Creat (&00)"
  490 PROCzero
  500 blk%?2=&00
  510 blk%!4=AFINET%
  520 blk%!8=SOCKSTREAM%
  530 blk%!12=0
  540 PROCosword
  550 sock%=blk%!4
  555 IF noresp% THEN ENDPROC
  560 PRINT "  socket = ";sock%
  570 ENDPROC
  580 :
  590 REM Try to make the socket non-blocking. If this fails, Recv
  600 REM may block forever - that is itself a useful result.
  610 DEF PROCnonblock
  620 PRINT "--- Socket_Ioctl (&12) FIONBIO"
  630 !buf%=1
  640 PROCzero
  650 blk%?2=&12
  660 blk%!4=sock%
  670 blk%!8=FIONBIO%
  680 blk%!12=buf%
  690 PROCosword
  700 IF blk%?3<>0 THEN PRINT "  *** non-blocking NOT set - Recv may hang"
  710 ENDPROC
  720 :
  730 DEF PROCconnect
  740 PRINT "--- Socket_Connect (&04)"
  750 PROCbuildsa
  760 PROCzero
  770 blk%?2=&04
  780 blk%!4=sock%
  790 blk%!8=sa%
  800 blk%!12=16
  810 PROCosword
  820 ENDPROC
  830 :
  840 DEF PROCsend(d$)
  850 LOCAL i%
  860 PRINT "--- Socket_Send (&08) ";LEN(d$);" bytes"
  870 FOR i%=1 TO LEN(d$)
  880   buf%?(i%-1)=ASC(MID$(d$,i%,1))
  890 NEXT
  900 PROCzero
  910 blk%?2=&08
  920 blk%!4=sock%
  930 blk%!8=buf%
  940 blk%!12=LEN(d$)
  950 blk%!16=0
  960 PROCosword
  970 ENDPROC
  980 :
  990 DEF PROCrecvloop
 1000 LOCAL n%,t%,k%
 1010 PRINT "--- Socket_Recv (&05)  ESCAPE to stop, 15s idle timeout"
 1020 PRINT STRING$(70,"-")
 1030 *FX229,1
 1040 t%=TIME
 1050 REPEAT
 1060   PROCzero
 1070   blk%?2=&05
 1080   blk%!4=sock%
 1090   blk%!8=buf%
 1100   blk%!12=255
 1110   blk%!16=0
 1120   PROCoswordq
 1130   n%=blk%!4
 1140   IF n%>0 THEN PROCshow(n%):t%=TIME
 1150   k%=INKEY(0)
 1160 UNTIL k%=27 OR (TIME-t%)>1500
 1170 *FX229,0
 1180 PRINT
 1190 PRINT STRING$(70,"-")
 1200 IF k%=27 THEN PRINT "(escape)" ELSE PRINT "(idle timeout)"
 1210 ENDPROC
 1220 :
 1230 DEF PROCclose
 1240 PRINT "--- Socket_Close (&10)"
 1250 PROCzero
 1260 blk%?2=&10
 1270 blk%!4=sock%
 1280 PROCosword
 1290 ENDPROC
 1300 :
 1310 REM ================ helpers ================
 1320 :
 1330 REM Build sockaddr_in at sa%. THIS LAYOUT IS THE GUESS.
 1340 REM Port is network byte order (big endian).
 1350 DEF PROCbuildsa
 1360 LOCAL i%,p%,q%,o%
 1370 FOR i%=0 TO 15
 1380   sa%?i%=0
 1390 NEXT
 1400 IF sa44% THEN sa%?0=16:sa%?1=AFINET%
 1410 IF NOT sa44% THEN sa%?0=AFINET%:sa%?1=0
 1420 sa%?2=port% DIV 256
 1430 sa%?3=port% MOD 256
 1440 REM dotted quad -> 4 bytes at +4
 1450 p%=1:o%=4
 1460 FOR i%=1 TO 4
 1470   q%=INSTR(ip$+".",".",p%)
 1480   sa%?o%=VAL(MID$(ip$,p%,q%-p%))
 1490   p%=q%+1:o%=o%+1
 1500 NEXT
 1510 PRINT "  sockaddr: ";
 1520 FOR i%=0 TO 15
 1530   PRINT FNhex(sa%?i%);" ";
 1540 NEXT
 1550 PRINT
 1560 ENDPROC
 1570 :
 1580 REM OSWORD with before/after dump of offsets 0-19
 1590 DEF PROCosword
 1600 PRINT "  send "; :PROCdump
 1610 PROCoswordq
 1620 PRINT "  recv "; :PROCdump
 1625 IF blk%?2<>0 THEN noresp%=TRUE:PRINT "  *** +2 NOT ZEROED - no module":ENDPROC
 1630 noresp%=FALSE
 1635 PRINT "  +3 result = ";blk%?3;
 1640 IF blk%?3=0 THEN PRINT " (ok)" ELSE PRINT " (ERROR)"
 1650 ENDPROC
 1660 :
 1670 DEF PROCoswordq
 1680 LOCAL A%,X%,Y%
 1690 A%=&C0
 1700 X%=blk% MOD 256
 1710 Y%=blk% DIV 256
 1720 CALL &FFF1
 1730 ENDPROC
 1740 :
 1750 DEF PROCzero
 1760 LOCAL i%
 1770 FOR i%=0 TO 27
 1780   blk%?i%=0
 1790 NEXT
 1800 blk%?0=28:blk%?1=28
 1802 REM +3 MUST be zero on entry - Sprow netprogapi.pdf. An earlier
 1804 REM version put a &FF sentinel here, which broke the call and
 1806 REM produced a false "nothing claimed OSWORD &C0" on hardware.
 1808 REM Presence is signalled by +2 being zeroed on exit instead.
 1810 blk%?3=0
 1812 ENDPROC
 1820 :
 1830 DEF PROCdump
 1840 LOCAL i%
 1850 FOR i%=0 TO 19
 1860   PRINT FNhex(blk%?i%);
 1870   IF (i% AND 3)=3 THEN PRINT "-"; ELSE PRINT " ";
 1880 NEXT
 1890 PRINT
 1900 ENDPROC
 1910 :
 1920 DEF PROCshow(n%)
 1930 LOCAL i%,c%
 1940 FOR i%=0 TO n%-1
 1950   c%=buf%?i%
 1960   IF c%=13 OR c%=10 THEN VDU c%:GOTO 1990
 1970   IF c%>=32 AND c%<127 THEN VDU c%:GOTO 1990
 1980   PRINT "<";FNhex(c%);">";
 1990 NEXT
 2000 ENDPROC
 2010 :
 2020 DEF FNhex(b%)=RIGHT$("0"+STR$~b%,2)
 2030 :
 2040 DEF PROCerr
 2050 *FX229,0
 2060 PRINT
 2070 PRINT "Error ";ERR;" at line ";ERL
 2080 REPORT:PRINT
 2090 ENDPROC
