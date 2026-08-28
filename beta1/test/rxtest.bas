   10 REM > RXTEST - does an adaptive read LOSE data?
   20 REM
   30 REM BEEBTERM drops characters during a burst (2026-08-19). The
   40 REM suspect is 5.5a's adaptive sizing: Socket_Recv satisfies the
   50 REM requested count exactly or returns &1E, and nothing has ever
   60 REM established what happens to the bytes already in the module's
   70 REM buffer when it says &1E. If they are discarded, every
   80 REM overshoot in the ramp loses data - and a throughput benchmark
   90 REM would never notice, because it only counts what arrived.
  100 REM
  110 REM The host sends "0123456789" over and over. Every byte is
  120 REM therefore predictable from the one before, so a gap is
  130 REM detectable rather than merely suspected.
  140 REM
  150 REM REVISED after the first run showed gaps in BOTH modes. The
  151 REM first version flooded 20000 bytes as fast as socat could
  152 REM push them, which overruns the module's buffer whatever the
  153 REM read size - so it could not tell overrun from discard.
  154 REM
  155 REM exp% bytes are now sent ONCE and the sender then holds the
  156 REM connection open. Small enough to sit entirely in the
  157 REM module's buffer, so there is no overrun to blame:
  158 REM
  160 REM   socat TCP-LISTEN:2324,reuseaddr,fork,bind=192.0.2.10 \
  165 REM     SYSTEM:'for i in $(seq 1 100); do printf 0123456789;
  166 REM              done; sleep 60'
  170 REM
  180 REM mode%=0 adaptive (the suspect), 1 = one byte per call (the
  190 REM control). Run both: same stream, and only one should lose.
  200 REM
  210 REM BASIC IV safe.
  220 :
  230 ip$="192.0.2.10":pt%=2324
  240 mode%=0:mx%=128
  245 exp%=1000
  250 :
  260 DIM b% 31,sa% 31,r% 1023,q% 3
  270 k%=-1:n%=0:e%=0:c%=0:pk%=0:sz%=1:last%=-1:fio%=-1:f%=0:ov%=0:s%=0:sh%=0
  280 ON ERROR PROCerr:END
  290 PRINT "RXTEST - ";
  300 IF mode%=0 THEN PRINT "adaptive" ELSE PRINT "one byte per call"
  305 REM Print the buffer address. On a 6502 co-pro this is a 16-bit
  306 REM address the host understands; on native ARM it is a 32-bit
  307 REM ARM address, and whether the Tube translates it is exactly
  308 REM what 2.4 says was never proven. If the count comes back right
  309 REM but the bytes are wrong, this is why.
  310 PROCopen
  315 PRINT "control block &";~b%;"  rx buffer &";~r%
  320 PROCfionread
  330 PRINT "receiving ";exp%;" bytes - stops after 5s of silence"
  340 T=TIME
  350 REPEAT
  360   PROCread
  370 UNTIL (TIME-T)>500 OR n%>=exp%
  380 PROCreport
  390 PROCclose
  400 END
  410 :
  420 REM ---- the read under test -----------------------------------------
  430 :
  440 DEF PROCread
  450 LOCAL i%,g%
  460 IF mode%=1 THEN sz%=1
  470 FOR i%=0 TO 27:b%?i%=0:NEXT
  480 b%?0=20:b%?1=8:b%?2=5
  490 b%!4=k%:b%!8=r%:b%!12=sz%:b%!16=8
  500 PROCosw
  510 c%=c%+1
  520 IF b%?3<>0 THEN PROCmiss:ENDPROC
  525 REM +4 must equal what was asked for. Anything else means the
  526 REM call did not deliver and +4 still holds the socket number we
  527 REM put there - reading r% then returns unwritten memory. The
  528 REM first run of this probe lacked the check and reported 1000
  529 REM bytes of garbage as "data lost".
  530 g%=b%!4
  532 REM A short count is REAL DATA, not a failure. Only a negative
  534 REM or an impossible count means nothing arrived.
  535 IF g%<0 OR g%>sz% THEN PROCbad(g%):ENDPROC
  540 IF g%<1 THEN ENDPROC
  545 IF g%<sz% THEN PROCshort(g%)
  550 T=TIME
  560 IF g%>pk% THEN pk%=g%
  570 FOR i%=0 TO g%-1
  580   PROCcheck(r%?i%)
  590 NEXT
  600 IF sz%<mx% AND mode%=0 AND g%=sz% THEN sz%=sz%*2
  610 ENDPROC
  612 :
  614 REM Fewer bytes than asked for, but they are still data. Count
  616 REM them and go back to probing from 1.
  618 DEF PROCshort(g%)
  620 sh%=sh%+1
  622 IF sh%<4 THEN PRINT "short: asked ";sz%;" got ";g%
  624 sz%=1
  626 ENDPROC
  628 :
  630 REM &1E. Note how many bytes were OUTSTANDING when it happened -
  640 REM that is the size of the hole if the module discards them.
  650 DEF PROCmiss
  660 f%=f%+1
  670 IF sz%>ov% THEN ov%=sz%
  680 sz%=1
  690 ENDPROC
  692 :
  694 REM Success reported, wrong count returned. Dump the block for
  696 REM the first few so the convention can be read off the screen.
  697 DEF PROCbad(g%)
  698 s%=s%+1
  699 IF s%<4 THEN PRINT "odd: asked ";sz%;" +2=";~b%?2;" +3=";~b%?3;" +4=";g%
  701 sz%=1
  702 ENDPROC
  705 :
  710 REM Every byte must be the previous one plus 1, wrapping 9 to 0.
  720 DEF PROCcheck(v%)
  730 LOCAL w%
  740 n%=n%+1
  750 IF last%<0 THEN last%=v%:ENDPROC
  760 w%=last%+1:IF w%>57 THEN w%=48
  770 IF v%<>w% THEN PROCgap(w%,v%)
  780 last%=v%
  790 ENDPROC
  800 :
  810 DEF PROCgap(want%,got%)
  820 e%=e%+1
  830 IF e%<6 THEN PRINT "gap at byte ";n%;": expected ";CHR$(want%);" got ";CHR$(got%)
  835 IF e%=6 THEN PRINT "(further gaps counted, not printed)"
  840 ENDPROC
  850 :
  860 REM ---- FIONREAD - is there a way to avoid overshooting at all? -----
  870 :
  880 REM If the module implements FIONREAD it will say how many bytes
  890 REM are waiting, and the terminal can ask for exactly that: no
  900 REM overshoot, no failed calls, no possible loss. That would be a
  910 REM better design than probing by trial and error.
  920 DEF PROCfionread
  930 LOCAL i%
  940 FOR i%=0 TO 27:b%?i%=0:NEXT
  950 b%?0=20:b%?1=8:b%?2=&12
  960 !q%=0
  970 b%!4=k%:b%!8=&4004667F:b%!12=q%
  980 PROCosw
  990 IF b%?3<>0 THEN PRINT "FIONREAD unsupported, r=&";~b%?3:ENDPROC
 1000 fio%=!q%
 1010 PRINT "FIONREAD accepted, reports ";fio%;" bytes waiting"
 1020 ENDPROC
 1030 :
 1040 REM ---- report -------------------------------------------------------
 1050 :
 1060 DEF PROCreport
 1070 PRINT STRING$(46,"-")
 1075 PRINT "expected         ";exp%
 1080 PRINT "bytes received   ";n%
 1090 PRINT "sequence gaps    ";e%;
 1100 IF e%=0 THEN PRINT "  (nothing missing)" ELSE PRINT "  *** DATA LOST"
 1110 PRINT "calls            ";c%
 1120 PRINT "failed (&1E)     ";f%
 1130 PRINT "largest read     ";pk%
 1132 PRINT "odd reads        ";s%
 1134 PRINT "short reads      ";sh%
 1140 PRINT "largest overshoot";ov%
 1150 PRINT
 1155 REM The whole payload fits in the module's buffer, so overrun
 1156 REM is ruled out and a gap can only be the read losing it.
 1160 IF e%>0 AND mode%=0 THEN PRINT "Adaptive read loses data - a failed"
 1162 IF e%>0 AND mode%=0 THEN PRINT "read discards the buffer. See 5.5a."
 1170 IF e%>0 AND mode%=1 THEN PRINT "One byte per call loses it too, so the"
 1172 IF e%>0 AND mode%=1 THEN PRINT "read size is NOT the cause."
 1180 IF e%=0 THEN PRINT "Clean. Earlier loss was buffer overrun, not"
 1182 IF e%=0 THEN PRINT "the read - the sender outran the Beeb."
 1190 ENDPROC
 1200 :
 1210 REM ---- socket plumbing ---------------------------------------------
 1220 :
 1230 DEF PROCopen
 1240 LOCAL i%
 1250 FOR i%=0 TO 27:b%?i%=0:NEXT
 1260 b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
 1270 PROCosw
 1275 PROCclaimed("creat")
 1280 k%=b%!4
 1290 IF b%?3<>0 OR k%<0 THEN PRINT "creat failed":END
 1300 PROCaddr
 1310 FOR i%=0 TO 27:b%?i%=0:NEXT
 1320 b%?0=20:b%?1=8:b%?2=4:b%!4=k%:b%!8=sa%:b%!12=16
 1330 PROCosw
 1335 PROCclaimed("connect")
 1340 IF b%?3<>0 THEN PRINT "connect failed r=&";~b%?3:END
 1350 PRINT "connected to ";ip$;":";pt%
 1360 ENDPROC
 1370 :
 1372 REM +2 is the command byte WE wrote, and 4.1 says LANManager
 1374 REM zeroes it on every call. If it survives, nothing claimed
 1376 REM OSWORD &C0 and every field is untouched - +4 reads back as
 1378 REM whatever we put there, which looks exactly like a plausible
 1379 REM socket number or byte count. nettest.bas has always tested
 1381 REM this; every other caller must too.
 1382 DEF PROCclaimed(w$)
 1384 IF b%?2=0 THEN ENDPROC
 1386 PRINT "*** NOTHING CLAIMED OSWORD &C0 (";w$;") - +2=";~b%?2
 1387 PRINT "No socket module on THIS machine. A co-processor needs"
 1388 PRINT "the call to reach the host's Sprow ROM - see 2.4, 7 Q1."
 1389 END
 1394 :
 1396 DEF PROCaddr
 1398 LOCAL i%,a%,z%,o%
 1400 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1410 sa%?0=16:sa%?1=2
 1420 sa%?2=pt% DIV 256:sa%?3=pt% MOD 256
 1430 a%=1:o%=4
 1440 FOR i%=1 TO 4
 1450   z%=INSTR(ip$+".",".",a%)
 1460   sa%?o%=VAL(MID$(ip$,a%,z%-a%))
 1470   a%=z%+1:o%=o%+1
 1480 NEXT
 1490 ENDPROC
 1500 :
 1510 DEF PROCclose
 1520 LOCAL i%
 1530 FOR i%=0 TO 27:b%?i%=0:NEXT
 1540 b%?0=20:b%?1=8:b%?2=&10:b%!4=k%
 1550 PROCosw
 1560 ENDPROC
 1570 :
 1572 REM CALL &FFF1 takes the OSWORD number from A% and the block
 1574 REM address from X% and Y%. Leave them unset and the call still
 1576 REM happens - to some other OSWORD, with some other block - and
 1578 REM nothing touches the control block, so +2 survives and +4
 1579 REM reads back whatever the caller put there. The first two runs
 1581 REM of this probe did exactly that and looked like a module that
 1583 REM was not answering. Set them on every call, not once.
 1585 DEF PROCosw
 1586 LOCAL A%,X%,Y%
 1587 A%=&C0:X%=b% MOD 256:Y%=b% DIV 256
 1588 CALL &FFF1
 1589 ENDPROC
 1590 :
 1592 DEF PROCerr
 1594 PRINT
 1600 PRINT "Error ";ERR;" at line ";ERL
 1610 REPORT:PRINT
 1620 ENDPROC
