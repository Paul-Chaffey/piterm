   10 REM > OSWSCAN - find which OSWORD the network ROM answers on
   20 REM Scans only HIGH-numbered OSWORDs (&80-&FF). Those use the
   30 REM send/recv length convention the socket API documents, and
   40 REM the range avoids the disc calls (&72 ADFS, &7F 1770).
   50 REM Command code &FF is in the API's "reserved" range, so a
   60 REM module that claims the call should just report an error.
   70 REM Sentinel is &AA, not &FF, because &FF is a plausible error
   80 REM code and would be indistinguishable from an untouched block.
   90 REM Some OSWORDs raise BASIC errors, so the loop is restartable.
  100 DIM b% 31
  110 f%=0:n%=&80
  120 PRINT "scanning OSWORD &80-&FF"
  130 ON ERROR PROCoops:GOTO 140
  140 REPEAT
  150   PROCtry
  160   n%=n%+1
  170 UNTIL n%>&FF
  180 PRINT "done, ";f%;" claimed"
  190 END
  200 :
  210 DEF PROCtry
  220 LOCAL i%
  230 FOR i%=0 TO 27:b%?i%=0:NEXT
  240 b%?0=28:b%?1=28:b%?2=&FF:b%?3=&AA
  250 A%=n%:X%=b% MOD 256:Y%=b% DIV 256
  260 CALL &FFF1
  270 IF b%?3<>&AA THEN PRINT "  &";~n%;" CLAIMED +3=";~b%?3;" +4=";~b%?4:f%=f%+1
  280 ENDPROC
  290 :
  300 DEF PROCoops
  310 REM Terse - these flow across the screen so a CLAIMED line
  320 REM further up is not scrolled away.
  330 PRINT "&";~n%;"=e";ERR;" ";
  340 n%=n%+1
  350 ENDPROC
