 3000 REM > NETPRESENT - presence test, per Sprow's netprogapi.pdf
 3010 REM Coexists with BEEBLINK (10-890) and OSWSCAN (2000-2300).
 3020 REM Start it with   GOTO 3000
 3030 REM
 3040 REM The documented method: issue Socket_Close with socket -1,
 3050 REM which can never be valid, then see whether LANManager
 3060 REM zeroed the subreason byte at +2.
 3070 REM NOTE +3 MUST be zero on entry. The earlier probe put a
 3080 REM sentinel there, which is why it wrongly reported nothing.
 3090 DIM w% 31
 3100 FOR i%=0 TO 31:w%?i%=0:NEXT
 3110 w%?0=8:w%?1=8
 3120 w%?2=&10
 3130 w%?3=0
 3140 w%!4=-1
 3150 A%=192:X%=w% MOD 256:Y%=w% DIV 256
 3160 CALL &FFF1
 3170 PRINT "+2=";~w%?2;"  +3=";~w%?3;"  +4=";w%!4
 3180 IF w%?2=0 THEN PRINT "PRESENT - OSWORD &C0 is answered" ELSE PRINT "ABSENT - +2 unchanged"
