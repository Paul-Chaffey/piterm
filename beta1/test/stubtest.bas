   10 REM > STUBTEST - exercise SOCKSTUB via OSWORD &C0
   20 REM Short on purpose: it must be typed in via *EXEC.
   30 DIM b% 31
   40 DIM u% 255
   50 PRINT "STUBTEST"
   60 PROCcall(&00,"Creat  ")
   70 PROCcall(&04,"Connect")
   80 FOR J%=1 TO 4:PROCrecv:NEXT
   90 PROCcall(&10,"Close  ")
  100 PRINT "STUBTEST end"
  110 END
  120 DEF PROCcall(c%,n$)
  130 PROCzero:b%?2=c%:PROCosw
  140 PRINT n$;" r=";~b%?3;" ret=";b%!4
  150 ENDPROC
  160 DEF PROCrecv
  170 LOCAL n%,i%
  180 PROCzero:b%?2=&05:b%?0=20:b%?1=8:b%!8=u%:b%!12=1:b%!16=8:PROCosw
  190 n%=b%!4
  200 PRINT "recv    r=";~b%?3;" n=";n%;" [";
  205 IF n%<1 THEN PRINT "] r3=";~b%?3:ENDPROC
  210 FOR i%=0 TO n%-1
  220 IF u%?i%>31 THEN VDU u%?i% ELSE PRINT "<";~u%?i%;">";
  230 NEXT
  240 PRINT "]"
  250 ENDPROC
  260 DEF PROCzero
  270 LOCAL i%
  280 FOR i%=0 TO 27:b%?i%=0:NEXT
  290 b%?0=28:b%?1=28:b%?3=0:REM +3 MUST be zero on entry
  300 ENDPROC
  310 DEF PROCosw
  320 LOCAL A%,X%,Y%
  330 A%=&C0:X%=b% MOD 256:Y%=b% DIV 256
  340 CALL &FFF1
  350 ENDPROC
