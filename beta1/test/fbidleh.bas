   10 REM > FBIDLEH - the HOST build of FBIDLE. Run it on the 6502 with NO
   12 REM co-processor: *EXEC FBIDLEH then RUN.
   15 REM
   20 REM Copro 15 dies within minutes with a socket merely EXISTING -
   25 REM FBIDLE4, created and never connected (specification.md 5.5b-quater).
   27 REM This is that same test on the host, and it decides where the fault
   28 REM lives: if the host survives ten minutes the crash is the
   29 REM co-processor and the Tube; if the host dies too the module has
   30 REM always been like this and BEEBTERM only ever got away with it.
   35 REM RESPROF caught the crash and it happened with the terminal
   40 REM completely idle: got frozen at 51063 for the last twenty seconds,
   45 REM reads climbing 245 an interval and every one of them empty, then
   50 REM nothing. So it is not the assembler, not the scroll, not the
   55 REM parser and not the flush - none of them were running.
   60 REM
   65 REM What runs when PTERM is idle is a socket poll, a reply check, a
   70 REM key check, a nap, and a heartbeat file write every three seconds.
   75 REM This strips that to the poll and the heartbeat, matching PTERM's
   80 REM rate of about eighty polls a second.
   85 REM
   90 REM   both builds crash    -> the module or the polling itself
   95 REM   only FBIDLE crashes  -> writing to LANManFS while a socket is
  100 REM                           open, ie two users of one network stack
  105 REM   neither crashes      -> the fault is in PTERM's own idle work
  110 REM
  115 REM Leave it running for five minutes. PTERM died after about three.
  120 :
  125 host$="192.0.2.10":port%=2323
  130 rf$="RESIDLE"
  135 mnowait%=8
  140 hbcs%=300
  145 hbfile%=TRUE
  147 bld$="0822c"
  150 REM mode 0 do not even connect - is the MACHINE stable on its own?
  155 REM mode 1 connect, then never poll - is holding a socket enough?
  160 REM mode 2 connect, poll once every pollcs% centiseconds - slowly
  165 REM mode 3 connect, poll flat out - the one that crashed at poll 4502
  170 REM        itself, or having a live TCP connection open?
  172 REM mode 4 CREATE a socket but never connect it - is it the socket
  175 mode%=4:pollcs%=50
  180 REM Switch the filing system away from LANManFS before the socket is
  185 REM made. LANManFS is a NETWORK filing system on the same interface,
  190 REM so a mounted share and a Sprow socket are two users of one stack -
  195 REM which would explain why the host, where BEEBTERM held connections
  200 REM for whole sessions, stayed up. Empty string leaves it alone.
  205 leavefs$=""
  210 :
  215 rf%=0:sock%=-1:err%=0:n%=0:e%=0:by%=0:hb%=0
  220 ON ERROR PROCerr:END
  225 DIM blk% 31, sa% 31, rx% 127
  230 IF leavefs$<>"" THEN PROCfs
  231 REM Say WHICH BUILD this is BEFORE the socket is made - a crash
  232 REM inside Socket_Creat must still leave the build on the screen.
  233 PRINT "FBIDLEH host build ";bld$
  234 PRINT "mode=";mode%;" hbfile=";hbfile%;" mnowait=";mnowait%
  235 IF mode%=4 THEN PROCmksock
  240 IF mode%>0 AND mode%<4 THEN PROCconnect
  248 PROChb("start mode="+STR$(mode%)+" b"+bld$)
  250 last%=TIME:plast%=TIME
  255 REPEAT
  260   IF mode%=3 THEN PROCpoll
  265   IF mode%=2 AND TIME-plast%>=pollcs% THEN plast%=TIME:PROCpoll
  270   PROCnap
  275   IF TIME-last%>=hbcs% THEN PROChb("tick")
  280 UNTIL FALSE
  285 END
  290 :
 1000 DEF PROCpoll
 1010 LOCAL g%
 1020 g%=FNtake(64)
 1030 n%=n%+1
 1040 IF g%>0 THEN by%=by%+g%
 1050 IF g%=-2 THEN e%=e%+1
 1060 ENDPROC
 1070 :
 1080 REM The FOR-loop nap, not the TIME spin - the spin is what FBSITN
 1085 REM proved fatal, so a test still using it would only re-find that.
 1090 DEF PROCnap
 1100 LOCAL i%
 1110 FOR i%=1 TO 20000:NEXT
 1130 ENDPROC
 1140 :
 1150 REM Appended and closed each time, so a crash keeps what came before.
 1160 DEF PROChb(w$)
 1170 LOCAL h%,s$
 1180 last%=TIME:hb%=hb%+1
 1190 s$=w$+" hb="+STR$(hb%)+" t="+STR$(TIME)+" polls="+STR$(n%)+" empty="+STR$(e%)+" bytes="+STR$(by%)
 1200 PRINT s$
 1210 IF NOT hbfile% THEN ENDPROC
 1220 h%=OPENUP(rf$)
 1230 IF h%=0 THEN h%=OPENOUT(rf$)
 1240 IF h%=0 THEN ENDPROC
 1250 PTR#h%=EXT#h%
 1260 FOR i%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,i%,1)):NEXT
 1270 BPUT#h%,13:BPUT#h%,10
 1280 CLOSE#h%
 1290 ENDPROC
 1300 :
 1310 DEF FNtake(nb%)
 1320 LOCAL i%
 1330 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1340 blk%?0=20:blk%?1=8:blk%?2=&05
 1350 blk%!4=sock%:blk%!8=rx%:blk%!12=nb%:blk%!16=mnowait%
 1360 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1370 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1380 err%=blk%?3
 1390 IF err%<>0 THEN =-2
 1400 =blk%!4
  1402 :
 1405 DEF PROCfs
 1406 PRINT "leaving the filing system: ";leavefs$
 1407 OSCLI(leavefs$)
 1408 ENDPROC
 1409 :
 1415 REM Just the socket, no connect. If THIS crashes it is not TCP at
 1416 REM all, it is the module having a socket at all.
 1417 DEF PROCmksock
 1418 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1419 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1420 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1421 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1422 sock%=blk%!4
 1423 PRINT "socket ";sock%;" created, NOT connected"
 1424 ENDPROC
 1425 :
 1426 DEF PROCconnect
 1427 LOCAL i%,a%,b%,o%
 1428 PROCmksock
 1490 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1500 sa%?0=16:sa%?1=2
 1510 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1520 a%=1:o%=4
 1530 FOR i%=1 TO 4
 1540   b%=INSTR(host$+".",".",a%)
 1550   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1560   a%=b%+1:o%=o%+1
 1570 NEXT
 1580 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1590 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1600 A%=&C0:X%=blk% AND 255:Y%=blk% DIV 256:CALL &FFF1
 1610 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1620 PRINT "connected to ";host$;":";port%
 1630 ENDPROC
 1640 :
 1650 DEF PROCstop(s$)
 1660 PROChb("fail "+s$)
 1670 PRINT "FBIDLE: ";s$
 1680 END
 1690 :
 1700 DEF PROCerr
 1710 PROChb("error "+STR$(ERR)+" line "+STR$(ERL))
 1720 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1730 REPORT:PRINT
 1740 ENDPROC
