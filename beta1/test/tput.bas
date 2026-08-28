   10 REM > TPUT - measure Socket_Recv throughput
   20 REM Run on the Pi co-processor. Answers the open question in
   30 REM specification.md 5.5c: is the direct path fast enough for a
   40 REM terminal, or is BEEBNET needed as a batching layer?
   50 REM
   60 REM Two numbers matter:
   70 REM  1. empty polls/sec - the cost of one OSWORD + Tube crossing
   80 REM     with no data. This is the hard ceiling on byte rate.
   90 REM  2. bytes/sec while data is streaming.
  100 :
  110 ip$="192.0.2.10":pt%=6502
  120 DIM b% 31,a% 31,r% 255,t% 255
  130 k%=-1
  140 ON ERROR PROCerr:END
  150 PRINT "TPUT - throughput measurement"
  160 PRINT "PAGE=&";~PAGE;"  HIMEM=&";~HIMEM
  170 PROCopen
  180 PRINT STRING$(46,"-")
  190 :
  200 REM ---- 1. empty poll rate ----
  210 PRINT "1 empty poll rate (5s, no data expected)"
  220 c%=0:T=TIME
  230 REPEAT
  240   PROCrecv1
  250   c%=c%+1
  260 UNTIL (TIME-T)>500
  270 PRINT "  ";c%;" polls in 5s = ";c% DIV 5;" calls/sec"
  280 PRINT "  (this is the ceiling: 1 byte per call)"
  290 :
  300 REM ---- 2. data rate ----
  310 PRINT "2 streaming - send data from the host now"
  320 n%=0:S=0:T=TIME
  330 REPEAT
  340   PROCrecv1
  350   IF b%!4=1 THEN PROCgot
  360 UNTIL (TIME-T)>1500
  370 IF n%<2 THEN PRINT "  no data arrived":GOTO 420
  380 E=TIME-S
  390 PRINT "  ";n%;" bytes in ";E;" centiseconds"
  400 IF E>0 THEN PRINT "  = ";(n%*100) DIV E;" bytes/sec"
  410 PRINT "  80x25 screenful (2000 bytes) would take ";
  415 IF n%>1 AND E>0 THEN PRINT (2000*E) DIV (n%*100);"s"
  420 PROCclose
  430 PRINT "TPUT done"
  440 END
  450 :
  460 REM Count a byte; start the clock on the first one, and keep
  470 REM the idle timeout from firing while data is still flowing.
  480 DEF PROCgot
  490 n%=n%+1
  500 IF n%=1 THEN S=TIME
  510 T=TIME
  520 ENDPROC
  530 :
  540 DEF PROCrecv1
  550 PROCzero:b%?0=20:b%?1=8:b%?2=5:b%!4=k%:b%!8=r%:b%!12=1:b%!16=8
  560 PROCosw
  570 ENDPROC
  580 :
  590 DEF PROCopen
  600 PROCzero:b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  610 PROCosw
  620 k%=b%!4
  630 IF b%?3<>0 OR k%<0 THEN PRINT "creat failed":END
  640 PROCaddr
  650 PROCzero:b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16
  660 PROCosw
  670 IF b%?3<>0 THEN PRINT "connect failed r=";~b%?3:END
  680 PRINT "connected to ";ip$;":";pt%
  690 ENDPROC
  700 :
  710 DEF PROCaddr
  720 LOCAL i%,p%,q%,o%
  730 FOR i%=0 TO 15:a%?i%=0:NEXT
  740 a%?0=16:a%?1=2
  750 a%?2=pt% DIV 256:a%?3=pt% MOD 256
  760 p%=1:o%=4
  770 FOR i%=1 TO 4
  780   q%=INSTR(ip$+".",".",p%)
  790   a%?o%=VAL(MID$(ip$,p%,q%-p%))
  800   p%=q%+1:o%=o%+1
  810 NEXT
  820 ENDPROC
  830 :
  840 DEF PROCclose
  850 IF k%<0 THEN ENDPROC
  860 PROCzero:b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
  870 PROCosw
  880 ENDPROC
  890 :
  900 DEF PROCzero
  910 LOCAL i%
  920 FOR i%=0 TO 27:b%?i%=0:NEXT
  930 ENDPROC
  940 :
  950 DEF PROCosw
  960 LOCAL A%,X%,Y%
  970 A%=192:X%=b% MOD 256:Y%=b% DIV 256
  980 CALL &FFF1
  990 ENDPROC
 1000 :
 1010 DEF PROCerr
 1020 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1030 REPORT:PRINT
 1040 ENDPROC
