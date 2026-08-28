   10 REM > FBMV - does the assembled block move work on real hardware?
   20 REM
   30 REM   CHAIN "FBMV"       copro 15, *ARMBASIC. Five seconds, no network.
   40 REM
   50 REM Writes RESMV to the share as well as printing, because the first
   60 REM version only printed and the result could not be read back here.
   70 REM A diagnostic nobody can retrieve is not a diagnostic.
   80 rf%=0
   90 ON ERROR PROCbad:END
  100 rf%=OPENOUT("RESMV")
  110 PROCw("[fbmv1]")
  120 PROCw("himem="+STR$~(HIMEM))
  130 PROCv_asm
  140 PROCw("fastmv="+STR$(fastmv%)+"  (-1 = assembled move in use, 0 = fell back)")
  150 IF NOT fastmv% THEN PROCw("FELL BACK - the self test at init did not pass"):PROCdone
  160 DIM a% 4095, b% 4095
  170 FOR i%=0 TO 4095:a%?i%=(i% AND 255):b%?i%=0:NEXT
  180 PROCv_mv(b%,a%+640,2560)
  190 bad%=0
  200 FOR i%=0 TO 2559
  210   IF b%?i%<>((i%+640) AND 255) THEN bad%=bad%+1
  220 NEXT
  230 PROCw("offset_move_2560 wrong="+STR$(bad%))
  240 IF b%?2560<>0 THEN PROCw("OVERRAN past the length") ELSE PROCw("stopped at the right byte")
  250 t=TIME
  260 FOR j%=1 TO 100:PROCv_mv(b%,a%,4096):NEXT
  270 PROCw("100x4096 cs="+STR$(TIME-t))
  280 REM And a real scroll-sized move, which is what actually matters.
  290 t=TIME
  300 FOR j%=1 TO 10:PROCv_mv(b%,a%,4096):NEXT
  310 PROCw("10x4096 cs="+STR$(TIME-t))
  320 PROCdone
  330 :
  340 DEF PROCdone
  350 PROCw("[end]")
  360 IF rf%<>0 THEN CLOSE#rf%
  370 rf%=0
  380 PRINT "FBMV done - RESMV is on the share."
  390 END
  400 :
  410 DEF PROCw(s$)
  420 LOCAL i%
  430 PRINT s$
  440 IF rf%=0 THEN ENDPROC
  450 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
  460 BPUT#rf%,13:BPUT#rf%,10
  470 ENDPROC
  480 :
  490 DEF PROCbad
  500 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
  510 PROCw("[end]")
  520 IF rf%<>0 THEN CLOSE#rf%
  530 rf%=0
  540 PRINT:PRINT "Error ";ERR;" at line ";ERL
  550 REPORT:PRINT
  560 ENDPROC
