   10 REM > FBIDLE - does an idle socket poll crash the machine on its own?
   15 REM
   20 REM   CHAIN "FBIDLE"     polls AND writes a heartbeat to the share
   25 REM   CHAIN "FBIDLE2"    polls, heartbeat to the SCREEN only
   30 REM
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
  145 hbfile%=FALSE
  150 REM mode 0 do not even connect - is the MACHINE stable on its own?
  155 REM mode 1 connect, then never poll - is holding a socket enough?
  160 REM mode 2 connect, poll once every pollcs% centiseconds - slowly
  165 REM mode 3 connect, poll flat out - the one that crashed at poll 4502
  170 REM        itself, or having a live TCP connection open?
  172 REM mode 4 CREATE a socket but never connect it - is it the socket
  173 REM mode 5 mode 4 with NO TIME READS AT ALL - see PROCquiet
  174 REM mode 6 mode 5 with TIME read every tdiv% naps - the RATE LADDER
  175 mode%=6:pollcs%=50
  176 REM doclen% TRUE sends Sprow's own block lengths (netprogapi.pdf):
  177 REM Creat and Connect 16/8, Recv and Send 20/8, Close 8/4. FALSE sends
  178 REM the 28/28 every call here used until 2026-08-22. See 5.5b-quaterbis.
  179 doclen%=FALSE:bld$="0822k":tdiv%=1:mksock%=FALSE:tper%=2:napn%=20000
  180 REM Switch the filing system away from LANManFS before the socket is
  185 REM made. LANManFS is a NETWORK filing system on the same interface,
  190 REM so a mounted share and a Sprow socket are two users of one stack -
  195 REM which would explain why the host, where BEEBTERM held connections
  200 REM for whole sessions, stayed up. Empty string leaves it alone.
  205 leavefs$=""
  206 REM tcall%: WHICH host call the gate makes. 0 TIME (OSWORD 1, R2),
  207 REM 1 INKEY(0) (OSBYTE 129, R2 but NOT TIME), 2 VDU 0 (R1, the VDU
  208 REM channel, and a documented no-op so nothing reaches the screen).
  209 tcall%=2
  210 :
  215 rf%=0:sock%=-1:err%=0:n%=0:e%=0:by%=0:hb%=0
  220 ON ERROR PROCerr:END
  225 DIM blk% 31, sa% 31, rx% 127
  230 IF leavefs$<>"" THEN PROCfs
  231 REM Say WHICH BUILD this is BEFORE the socket is made - a crash
  232 REM inside Socket_Creat must still leave the build on the screen.
  233 PRINT "FBIDLE copro build ";bld$
  234 PRINT "mode=";mode%;" tdiv=";tdiv%;" tper=";tper%;" tcall=";tcall%;" mksock=";mksock%
  235 IF mode%>=4 AND mksock% THEN PROCmksock
  240 IF mode%>0 AND mode%<4 THEN PROCconnect
  248 PROChb("start mode="+STR$(mode%)+" doclen="+STR$(doclen%)+" b"+bld$)
  249 IF mode%=5 OR mode%=6 THEN PROCquiet
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
 1110 FOR i%=1 TO napn%:NEXT
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
 1335 REM 20/8 is already Sprow's figure for Recv, so doclen% does not enter.
 1340 blk%?0=20:blk%?1=8:blk%?2=&05
 1350 blk%!4=sock%:blk%!8=rx%:blk%!12=nb%:blk%!16=mnowait%
 1360 SYS "OS_Word",&C0,blk%
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
 1419 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1:IF doclen% THEN blk%?0=16:blk%?1=8
 1420 SYS "OS_Word",&C0,blk%
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
 1590 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16:IF doclen% THEN blk%?0=16:blk%?1=8
 1600 SYS "OS_Word",&C0,blk%
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
 1750 :
 1760 REM mode 5. Mode 4 died in 27 seconds with the parasite doing nothing
 1770 REM but nap and read TIME. TIME on a co-processor is a HOST read, so
 1780 REM every pass of that loop is a Tube transaction over R2, and the only
 1790 REM other thing running is the module's interrupt handler, which an
 1800 REM open socket is what activates. This removes the TIME reads entirely
 1810 REM and leaves the heartbeat on R1, the VDU channel.
 1820 REM
 1830 REM   lives   the crash needs Tube traffic AND an open socket, which
 1840 REM           narrows it to a race between the two and makes the rate
 1850 REM           the next thing to vary
 1860 REM   dies    an open socket kills the machine with the parasite
 1870 REM           quiet, so the parasite is not party to it at all
 1880 REM
 1890 REM TIME is read only to calibrate, for one second, and then never
 1900 REM again - so the count is in naps and the wall clock is yours.
 1901 REM
 1902 REM THREE KNOBS, orthogonal on purpose, all set near line 179.
 1903 REM
 1904 REM tdiv% is the RATE. The gate fires every tdiv% naps, tper% is how
 1905 REM many calls each firing makes, napn% is the nap length - so the rate
 1906 REM is about nps%*tper%/tdiv%, and napn% raises it above anything mode
 1907 REM 4 reached. A NEGATIVE tdiv% is firings per second, resolved after
 1908 REM calibration: 0 never, -1 once a second, 1 every nap.
 1909 REM mksock% is whether a socket is made at all.
 1910 REM tcall% is WHICH call - 0 TIME, 1 INKEY(0), 2 VDU 0. See line 206.
 1911 REM
 1912 REM WHAT IS ESTABLISHED, 2026-08-22, copro 15:
 1913 REM
 1914 REM Tube traffic crashes this machine and a socket is NOT required.
 1915 REM The socket only makes it arrive about 3.6 times sooner. ANY R2
 1916 REM call does it and INKEY(0) is worse than TIME, so PTERM cannot be
 1917 REM tuned out of it - polling a socket IS an R2 call.
 1918 REM
 1919 REM 0822f was meant as a positive control and did not die. The reason
 1920 REM is line 265: BBC BASIC's AND does NOT short-circuit, so
 1921 REM   IF mode%=2 AND TIME-plast%>=pollcs% THEN ...
 1922 REM reads TIME every pass even at mode 4 where mode%=2 is false, on
 1923 REM top of line 275. Mode 4 was TWO reads a pass and 0822f was one -
 1924 REM a rate point, not a failed control.
 1925 REM
 1926 REM 0822k asks the last cheap question: VDU 0 is R1, so if that
 1927 REM survives at rate the fault is one channel, not the whole Tube.
 1928 REM
 1929 REM But see TUBEBARE, which matters more: the LANMANAGER ROM has been
 1930 REM active in EVERY run ever made here, with a socket or without one.
 1931 REM
 1932 REM RESULTS - append here, the numbers run to 1949:
 1933 REM   build    calls/pass  socket     tcall      result
 1934 REM   mode 5   0                yes   -          passed 600s
 1935 REM   0822f    1                yes   0 TIME     passed 60s+
 1936 REM   mode 4   2                yes   0 TIME     dead 24-27s
 1937 REM   0822g    2                yes   0 TIME     dead 24s
 1938 REM   0822h    2                NO    0 TIME     dead 87s
 1939 REM   0822j    2                NO    1 INKEY    dead 24s
 1950 DEF PROCquiet
 1952 LOCAL i%,c%,t0%
 1954 t0%=TIME:c%=0
 1956 REPEAT:PROCnap:c%=c%+1:UNTIL TIME-t0%>=100
 1958 nps%=c%:IF nps%<1 THEN nps%=1
 1960 PRINT "calibrated ";nps%;" naps/sec"
 1962 IF tdiv%<0 THEN tdiv%=nps% DIV (-tdiv%):IF tdiv%<1 THEN tdiv%=1
 1964 c%=0:r%=0
 1966 IF tdiv%>0 THEN PRINT "TIME read every ";tdiv%;" naps" ELSE PRINT "TIME never read again"
 1980 REPEAT
 1990   PROCnap
 2000   c%=c%+1
 2005   IF tdiv%>0 THEN IF c% MOD tdiv%=0 THEN PROCrd
 2010   IF c% MOD (nps%*3)=0 THEN PRINT "quiet naps=";c%;" approx ";c% DIV nps%;"s reads=";r%
 2020 UNTIL FALSE
 2030 ENDPROC
 2040 :
 2050 REM tper% Tube transactions each time the gate fires. Mode 4 did TWO
 2060 REM per pass, not one: line 265 is
 2070 REM   IF mode%=2 AND TIME-plast%>=pollcs% THEN ...
 2080 REM and BBC BASIC's AND does NOT short-circuit, so TIME is read there
 2090 REM every pass even at mode 4 where mode%=2 is false, on top of the
 2100 REM read at line 275. Build 0822f ran ONE read per pass, which is half
 2110 REM mode 4's rate, and it passed a minute where mode 4 died at 24s.
 2120 REM That is a rate point, not a failed control.
 2130 DEF PROCrd
 2140 LOCAL k%
 2150 FOR k%=1 TO tper%
 2152   IF tcall%=0 THEN junk%=TIME
 2154   IF tcall%=1 THEN junk%=INKEY(0)
 2156   IF tcall%=2 THEN VDU 0
 2158 NEXT
 2160 r%=r%+tper%
 2170 ENDPROC
