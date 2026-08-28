   10 REM > TPUT3 - adaptive read size, many bytes per OSWORD call
   20 REM
   30 REM Everything so far read ONE byte per call, because §5.5a says
   40 REM Socket_Recv satisfies the requested count exactly or not at
   50 REM all. But MSG_DONTWAIT (&1E) tells us WHEN it cannot - so we
   60 REM can probe: ask for a lot, and back off until it succeeds.
   70 REM
   80 REM Strategy: start at 1 (cheap when idle), double on success,
   90 REM halve on failure. Idle polling costs one call; a burst
  100 REM ramps to 128 bytes per call within a few iterations.
  110 REM
  120 REM If this works, the per-byte Tube cost collapses and BEEBNET
  130 REM is unnecessary. See specification.md 5.5c.
  140 :
  150 ip$="192.0.2.10":pt%=6502
  160 DIM b% 31,a% 31,r% 255
  170 k%=-1:mx%=128
  180 ON ERROR PROCerr:END
  190 PRINT "TPUT3 - adaptive read size"
  200 PROCopen
  210 PRINT STRING$(46,"-")
  220 :
  230 FOR i%=0 TO 27:b%?i%=0:NEXT
  240 b%?0=20:b%?1=8
  250 b%!8=r%:b%!16=8
  260 :
  270 PRINT "streaming - send data now (20s)"
  280 n%=0:c%=0:S=0:L=0:d%=0:T=TIME:sz%=1:pk%=0
  290 REPEAT
  300   b%?2=5:b%?3=0:b%!4=k%:b%!12=sz%
  310   CALL &FFF1
  320   c%=c%+1
  330   IF b%!4=sz% THEN PROCgot ELSE PROCless
  340 UNTIL (TIME-T)>2000
  350 IF n%<2 THEN PRINT "no data arrived":GOTO 420
  355 REM Measure ONLY first success -> last success. The previous
  356 REM version ran S to loop-exit, which included the 20s idle
  357 REM timeout and made the rate look ~12x worse than it is.
  360 E=L-S
  370 PRINT n%;" bytes, ";d%;" reads, ";c%;" calls total"
  375 PRINT "burst took ";E;" cs"
  380 IF E>0 THEN PRINT "= ";(n%*100) DIV E;" bytes/sec"
  390 IF d%>0 THEN PRINT "= ";n% DIV d%;" bytes per successful read"
  400 PRINT "largest successful read: ";pk%
  410 IF n%>1 THEN PRINT "2000 bytes would take ";(2000*E) DIV n%;" cs"
  420 PROCclose
  430 PRINT "TPUT3 done"
  440 END
  450 :
  460 REM Success: bank the bytes and try for more next time.
  470 DEF PROCgot
  480 n%=n%+sz%
  485 d%=d%+1
  490 IF sz%>pk% THEN pk%=sz%
  500 IF d%=1 THEN S=TIME
  505 L=TIME
  510 T=TIME
  520 IF sz%<mx% THEN sz%=sz%*2
  530 ENDPROC
  540 :
  550 REM &1E - could not satisfy that count. Back off.
  560 DEF PROCless
  570 IF sz%>1 THEN sz%=sz% DIV 2
  580 ENDPROC
  590 :
  600 DEF PROCopen
  610 A%=192:X%=b% MOD 256:Y%=b% DIV 256
  620 FOR i%=0 TO 27:b%?i%=0:NEXT
  630 b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  640 CALL &FFF1
  650 k%=b%!4
  660 IF b%?3<>0 OR k%<0 THEN PRINT "creat failed":END
  670 PROCaddr
  680 FOR i%=0 TO 27:b%?i%=0:NEXT
  690 b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16
  700 CALL &FFF1
  710 IF b%?3<>0 THEN PRINT "connect failed r=";~b%?3:END
  720 PRINT "connected to ";ip$;":";pt%
  730 ENDPROC
  740 :
  750 DEF PROCaddr
  760 LOCAL i%,p%,q%,o%
  770 FOR i%=0 TO 15:a%?i%=0:NEXT
  780 a%?0=16:a%?1=2
  790 a%?2=pt% DIV 256:a%?3=pt% MOD 256
  800 p%=1:o%=4
  810 FOR i%=1 TO 4
  820   q%=INSTR(ip$+".",".",p%)
  830   a%?o%=VAL(MID$(ip$,p%,q%-p%))
  840   p%=q%+1:o%=o%+1
  850 NEXT
  860 ENDPROC
  870 :
  880 DEF PROCclose
  890 IF k%<0 THEN ENDPROC
  900 FOR i%=0 TO 27:b%?i%=0:NEXT
  910 b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
  920 CALL &FFF1
  930 ENDPROC
  940 :
  950 DEF PROCerr
  960 PRINT:PRINT "Error ";ERR;" at line ";ERL
  970 REPORT:PRINT
  980 ENDPROC
