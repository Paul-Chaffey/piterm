 2000 REM > OSWSCAN - coexists with BEEBLINK (which occupies 10-890)
 2010 REM Type this in ON TOP of the program already in memory.
 2020 REM Nothing is overwritten - the line numbers do not collide
 2030 REM and it uses its own variables (q%, not b%).
 2040 REM Start it with   GOTO 2000
 2050 REM NOT with RUN, which would restart BEEBLINK instead.
 2060 DIM q% 31
 2070 f%=0:n%=&80
 2080 PRINT "scanning OSWORD &80-&FF"
 2090 ON ERROR PROCoops2:GOTO 2100
 2100 REPEAT
 2110   PROCtry2
 2120   n%=n%+1
 2130 UNTIL n%>&FF
 2140 PRINT
 2150 PRINT "done, ";f%;" claimed"
 2160 END
 2170 :
 2180 DEF PROCtry2
 2190 LOCAL i%
 2200 FOR i%=0 TO 27:q%?i%=0:NEXT
 2210 q%?0=28:q%?1=28:q%?2=&FF:q%?3=&AA
 2220 A%=n%:X%=q% MOD 256:Y%=q% DIV 256
 2230 CALL &FFF1
 2240 IF q%?3<>&AA THEN PRINT "  &";~n%;" CLAIMED +3=";~q%?3;" +4=";~q%?4:f%=f%+1
 2250 ENDPROC
 2260 :
 2270 DEF PROCoops2
 2280 PRINT "&";~n%;"=e";ERR;" ";
 2290 n%=n%+1
 2300 ENDPROC
