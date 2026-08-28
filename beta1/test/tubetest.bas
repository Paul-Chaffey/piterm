   10 REM > TUBETEST - does OSWORD &C0 work from the co-processor?
   20 REM Run on the Pi co-processor with the Tube enabled.
   30 REM Answers specification.md section 5.6.
   40 REM
   50 REM The real question is NOT whether the control block crosses
   60 REM the Tube - netprogapi.pdf says it does, capped at 128 bytes
   70 REM each way - but whether the BUFFER POINTERS inside it are
   80 REM usable by the host. Socket_Connect passes a pointer to a
   90 REM sockaddr, so if connect succeeds, pointers survive and
  100 REM BEEBNET may be unnecessary.
  110 :
  120 ip$="192.0.2.10":pt%=6502
  130 DIM b% 31,a% 31,r% 255,t% 255
  140 k%=-1
  150 ON ERROR PROCerr:END
  160 PRINT "TUBETEST"
  170 PRINT "PAGE=&";~PAGE;"  HIMEM=&";~HIMEM
  180 PRINT STRING$(46,"-")
  190 :
  200 REM ---- 1. presence: passes NO pointers ----
  210 PROCzero:b%?0=8:b%?1=8:b%?2=&10:b%!4=-1
  220 PROCosw
  230 PRINT "1 presence  +2=";~b%?2;" +3=";~b%?3
  240 IF b%?2<>0 THEN PRINT "  FAIL - OSWORD &C0 unanswered":END
  250 PRINT "  OK - control block crosses the Tube"
  260 :
  270 REM ---- 2. Socket_Creat: still no pointers ----
  280 PROCzero:b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  290 PROCosw
  300 k%=b%!4
  310 PRINT "2 creat     +3=";~b%?3;" sock=";k%
  320 IF b%?3<>0 OR k%<0 THEN PRINT "  FAIL":END
  330 PRINT "  OK"
  340 :
  350 REM ---- 3. Socket_Connect: THIS PASSES A POINTER ----
  360 PROCaddr
  370 PROCzero:b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16
  380 PROCosw
  390 PRINT "3 connect   +3=";~b%?3
  400 IF b%?3<>0 THEN PRINT "  FAIL - pointers do NOT cross":PROCclose:END
  410 PRINT "  OK *** POINTERS CROSS THE TUBE ***"
  420 :
  430 REM ---- 4. Socket_Send: also passes a pointer ----
  440 n%=FNput("TUBETEST speaking from the co-processor")
  450 PROCzero:b%?0=20:b%?1=8:b%?2=8:b%!4=k%:b%!8=t%:b%!12=n%
  460 PROCosw
  470 PRINT "4 send      +3=";~b%?3;" sent=";b%!4
  480 :
  490 REM ---- 5. Socket_Recv: one byte per call, see spec 5.5a ----
  500 PRINT "5 recv - listening 10s, type at the host end"
  510 T=TIME
  520 REPEAT
  530   PROCzero:b%?0=20:b%?1=8:b%?2=5:b%!4=k%:b%!8=r%:b%!12=1:b%!16=8
  540   PROCosw
  550   IF b%!4=1 THEN VDU r%?0:T=TIME
  560 UNTIL (TIME-T)>1000
  570 PRINT
  580 PROCclose
  590 PRINT "TUBETEST done"
  600 END
  610 :
  620 REM Fill the transmit buffer, return the length.
  630 DEF FNput(s$)
  640 LOCAL i%
  650 FOR i%=1 TO LEN(s$)
  660   t%?(i%-1)=ASC(MID$(s$,i%,1))
  670 NEXT
  680 t%?LEN(s$)=13:t%?(LEN(s$)+1)=10
  690 =LEN(s$)+2
  700 :
  710 REM sockaddr_in - confirmed layout, netprogapi.pdf
  720 DEF PROCaddr
  730 LOCAL i%,p%,q%,o%
  740 FOR i%=0 TO 15:a%?i%=0:NEXT
  750 a%?0=16:a%?1=2
  760 a%?2=pt% DIV 256:a%?3=pt% MOD 256
  770 p%=1:o%=4
  780 FOR i%=1 TO 4
  790   q%=INSTR(ip$+".",".",p%)
  800   a%?o%=VAL(MID$(ip$,p%,q%-p%))
  810   p%=q%+1:o%=o%+1
  820 NEXT
  830 ENDPROC
  840 :
  850 DEF PROCclose
  860 IF k%<0 THEN ENDPROC
  870 PROCzero:b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
  880 PROCosw
  890 ENDPROC
  900 :
  910 REM +3 MUST be zero on entry - netprogapi.pdf
  920 DEF PROCzero
  930 LOCAL i%
  940 FOR i%=0 TO 27:b%?i%=0:NEXT
  950 ENDPROC
  960 :
  970 DEF PROCosw
  980 LOCAL A%,X%,Y%
  990 A%=192:X%=b% MOD 256:Y%=b% DIV 256
 1000 CALL &FFF1
 1010 ENDPROC
 1020 :
 1030 DEF PROCerr
 1040 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1050 REPORT:PRINT
 1060 ENDPROC
