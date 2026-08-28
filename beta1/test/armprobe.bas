   10 REM > ARMPROBE - is the b-em ARM co-processor the language FBVDU
   20 REM ships in, and does it answer the SWI the engine is built on?
   30 REM
   40 REM ARM ONLY. Half of this is a syntax error on BASIC IV, which is
   50 REM the point: if it runs at all we are on BASIC V.
   60 :
   70 ON ERROR PROCerr:END
   80 what$="start"
   90 PRINT "PAGE  &";~PAGE
  100 PRINT "HIMEM &";~HIMEM
  110 PRINT "free   ";(HIMEM-PAGE) DIV 1024;"K"
  120 :
  130 what$="BASIC V syntax"
  140 n%=0
  150 WHILE n%<3:n%+=1:ENDWHILE
  160 PRINT "WHILE and += work, so this is BASIC V"
  170 CASE n% OF
  180   WHEN 3: PRINT "CASE works too"
  190   OTHERWISE PRINT "CASE gave ";n%
  200 ENDCASE
  210 :
  220 what$="OS_ReadVduVariables"
  230 DIM q% 63,r% 63
  240 !q%=148:q%!4=150:q%!8=6:q%!12=-1
  250 SYS "OS_ReadVduVariables",q%,r%
  260 PRINT "screen start &";~!r%
  270 PRINT "screen size  ";r%!4
  280 PRINT "bytes/line   ";r%!8
  290 :
  300 what$="OS_Byte"
  310 SYS "OS_Byte",129,0,255 TO ,a%
  320 PRINT "OS_Byte 129 returned ";a%
  330 :
  340 PRINT "[armok]"
  350 END
  360 :
  370 DEF PROCerr
  380 PRINT
  390 PRINT "failed during: ";what$
  400 PRINT "error ";ERR;" at line ";ERL
  410 REPORT:PRINT
  420 PRINT "[armbad]"
  430 ENDPROC
