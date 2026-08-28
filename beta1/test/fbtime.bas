   10 REM > FBTIME - where does the time go, per VT operation?
   20 REM
   30 REM Phase 3 found a 582-byte capture taking 33 seconds and the first two
   40 REM guesses were both wrong: it was not BGET# per byte, and it was not
   50 REM only PROCv_fill. This measures each operation through the real
   60 REM PROCv_write path instead of guessing again.
   70 :
   80 cols%=80:rows%=64
   90 cw%=8:ch%=8
  100 md%=21:vdu%=0:pivdu%=2
  110 sim%=TRUE
  120 glass%=FALSE
  130 :
  140 ON ERROR PROCerr:END
  150 PROCv_boot
  160 IF vfail$<>"" THEN PRINT "cannot start: ";vfail$:END
  170 e$=CHR$(27)
  180 :
  190 PROCt("1000 plain glyphs",STRING$(50,"x"),20)
  200 PROCt("100 RIS",e$+"c",100)
  210 PROCt("100 alt in and out",e$+"[?1049h"+e$+"[?1049l",100)
  220 PROCt("100 newlines at the foot",e$+"[64;1H"+CHR$(10),100)
  230 PROCt("100 cursor moves",e$+"[10;20H",100)
  240 PROCt("100 SGR changes",e$+"[31;44m",100)
  250 PROCt("100 EL 2",e$+"[2K",100)
  260 PROCt("100 ED 2",e$+"[2J",100)
  270 PROCt("100 IL",e$+"[1;1H"+e$+"[L",100)
  280 PROCt("300 UTF-8 box glyphs",STRING$(10,CHR$(&E2)+CHR$(&94)+CHR$(&80)),30)
  290 PRINT "[timeok]"
  300 END
  310 :
10000 DEF PROCt(n$,s$,r%)
10010 LOCAL i%,t
10020 t=TIME
10030 FOR i%=1 TO r%:PROCv_writes(s$):NEXT
10040 PRINT n$;TAB(26);TIME-t;" cs"
10050 ENDPROC
10060 :
10070 DEF PROCerr
10080 PRINT:PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
10090 REPORT:PRINT
10100 ENDPROC
