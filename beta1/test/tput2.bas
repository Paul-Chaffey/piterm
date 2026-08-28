   10 REM > TPUT2 - is the poll rate limited by BASIC or by the Tube?
   20 REM
   30 REM TPUT measured 265 polls/sec, but each poll ran PROCzero -
   40 REM 28 interpreted BASIC iterations clearing a block that is
   50 REM then overwritten anyway. This version sets up the control
   60 REM block ONCE and touches only the three bytes the call
   70 REM consumes each time (+2 subreason, +3 must-be-zero,
   80 REM +4 socket, which the call overwrites with the result).
   90 REM
  100 REM If the rate jumps, BASIC was the bottleneck and the direct
  110 REM path may be viable. If it barely moves, the Tube round trip
  120 REM dominates and BEEBNET must batch. See spec 5.5c.
  130 :
  140 ip$="192.0.2.10":pt%=6502
  150 DIM b% 31,a% 31,r% 255
  160 k%=-1
  170 ON ERROR PROCerr:END
  180 PRINT "TPUT2"
  190 PROCopen
  200 PRINT STRING$(46,"-")
  210 :
  220 REM ---- set the block up once ----
  230 FOR i%=0 TO 27:b%?i%=0:NEXT
  240 b%?0=20:b%?1=8
  250 b%!8=r%:b%!12=1:b%!16=8
  260 :
  270 PRINT "1 lean poll rate (5s, no data expected)"
  280 c%=0:T=TIME
  290 REPEAT
  300   b%?2=5:b%?3=0:b%!4=k%
  310   CALL &FFF1
  320   c%=c%+1
  330 UNTIL (TIME-T)>500
  340 PRINT "  ";c%;" polls in 5s = ";c% DIV 5;" calls/sec"
  350 PRINT "  (TPUT with PROCzero managed 265/sec)"
  360 :
  370 PRINT "2 streaming - send data now"
  380 n%=0:S=0:T=TIME
  390 REPEAT
  400   b%?2=5:b%?3=0:b%!4=k%
  410   CALL &FFF1
  420   IF b%!4=1 THEN PROCgot
  430 UNTIL (TIME-T)>1000
  440 IF n%<2 THEN PRINT "  no data arrived":GOTO 490
  450 E=TIME-S
  460 PRINT "  ";n%;" bytes in ";E;" centiseconds"
  470 IF E>0 THEN PRINT "  = ";(n%*100) DIV E;" bytes/sec"
  480 IF E>0 THEN PRINT "  2000-byte screenful = ";(2000*E) DIV (n%*100);"s"
  490 PROCclose
  500 PRINT "TPUT2 done"
  510 END
  520 :
  530 DEF PROCgot
  540 n%=n%+1
  550 IF n%=1 THEN S=TIME
  560 T=TIME
  570 ENDPROC
  580 :
  590 REM A% must be 192 for every OSWORD call; X%/Y% point at b%.
  600 REM Set once here, since CALL preserves them between calls.
  610 DEF PROCopen
  620 A%=192:X%=b% MOD 256:Y%=b% DIV 256
  630 FOR i%=0 TO 27:b%?i%=0:NEXT
  640 b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  650 CALL &FFF1
  660 k%=b%!4
  670 IF b%?3<>0 OR k%<0 THEN PRINT "creat failed":END
  680 PROCaddr
  690 FOR i%=0 TO 27:b%?i%=0:NEXT
  700 b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16
  710 CALL &FFF1
  720 IF b%?3<>0 THEN PRINT "connect failed r=";~b%?3:END
  730 PRINT "connected to ";ip$;":";pt%
  740 ENDPROC
  750 :
  760 DEF PROCaddr
  770 LOCAL i%,p%,q%,o%
  780 FOR i%=0 TO 15:a%?i%=0:NEXT
  790 a%?0=16:a%?1=2
  800 a%?2=pt% DIV 256:a%?3=pt% MOD 256
  810 p%=1:o%=4
  820 FOR i%=1 TO 4
  830   q%=INSTR(ip$+".",".",p%)
  840   a%?o%=VAL(MID$(ip$,p%,q%-p%))
  850   p%=q%+1:o%=o%+1
  860 NEXT
  870 ENDPROC
  880 :
  890 DEF PROCclose
  900 IF k%<0 THEN ENDPROC
  910 FOR i%=0 TO 27:b%?i%=0:NEXT
  920 b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
  930 CALL &FFF1
  940 ENDPROC
  950 :
  960 DEF PROCerr
  970 PRINT:PRINT "Error ";ERR;" at line ";ERL
  980 REPORT:PRINT
  990 ENDPROC
