   10 REM > FBNETW - add a Hosts line to the module's Choices file
   20 REM
   30 REM   co-processor OFF, share mounted:
   40 REM       NEW  then  *EXEC FBNETW  then  RUN
   50 REM   then CTRL-BREAK for the module to re-read it.
   60 REM
   70 REM RUN FBNET FIRST. This rewrites the module's non-volatile
   80 REM configuration, and RESSTRT is the byte-exact copy of what was
   90 REM there before.
  100 REM
  110 REM OSFile A=0 replaces the WHOLE file - there is no append. So this
  120 REM loads what is there, adds one line on the end, and writes the
  130 REM lot back. The module checks that every line is 80 bytes or fewer
  140 REM including the carriage return, and checks nothing else: "the
  150 REM text itself is not checked for valid syntax in any way".
  160 REM
  170 REM The file ends "# Hosts",CR,"#",CR, so appending puts the new
  180 REM line under the Hosts heading without moving anything.
  190 REM
  200 REM Hosts is consulted BEFORE the DNS, so this works whether or not
  210 REM the router knows the name - and it is one fewer thing between
  220 REM the machine and its files.
  230 REM
  240 REM Set restore%=TRUE to put NETBAK back instead. That is the way
  250 REM out if anything here goes wrong.
  260 :
  262 REM TWO experiments, one at a time - never both in one write, or a
  264 REM failure says nothing about which line caused it.
  266 REM   mount%=FALSE  add "192.0.2.10 deskbox" to Hosts
  268 REM   mount%=TRUE   add a speculative "Mount" directive to see
  269 REM                 whether the module honours one. Undocumented,
  270 REM                 and the module checks only line LENGTH - "the
  271 REM                 text itself is not checked for valid syntax in
  272 REM                 any way" - so a line it does not know should be
  273 REM                 ignored rather than refused. NETBAK is the way back.
  274 restore%=FALSE
  275 mount%=FALSE
  280 ha$="192.0.2.10":hn$="deskbox"
  285 IF mount% THEN add$="Mount \\"+ha$+"\beeb":key$="Mount " ELSE add$=ha$+" "+hn$:key$=hn$
  290 bk$="NETBAK"
  300 nm$="Choices:Internet.Startup"
  310 ON ERROR PROCerr:END
  320 DIM nm% 31,blk% 17,buf% 2047
  330 $nm%=nm$
  340 IF restore% THEN PROCrestore:END
  350 t%=FNcat
  360 IF t%=0 THEN PRINT "Not found - is LANManFS selected?":END
  370 ln%=blk%!10
  380 PRINT "current length ";ln%
  390 IF ln%<1 OR ln%>1900 THEN PRINT "Length ";ln%;" is not usable - stopping.":END
  400 PROCload
  410 IF FNfind(key$)>=0 THEN PRINT "'";key$;"' is already in the file - nothing to do.":END
  420 REM Back up only while the file is FULLY pristine - neither line
  430 REM present - so the second experiment cannot overwrite the good
  440 REM copy with the result of the first.
  445 IF FNfind(hn$)>=0 OR FNfind("Mount ")>=0 THEN PRINT "already modified - keeping the existing ";bk$:GOTO 460
  450 OSCLI("SAVE "+bk$+" "+STR$~buf%+" "+STR$~(buf%+ln%)):PRINT "backed up to ";bk$
  460 l$=add$
  470 IF LEN(l$)+1>80 THEN PRINT "line too long for the module - stopping.":END
  480 FOR i%=1 TO LEN(l$):buf%?(ln%+i%-1)=ASC(MID$(l$,i%,1)):NEXT
  490 ln%=ln%+LEN(l$)
  500 buf%?ln%=13:ln%=ln%+1
  510 PROCsave(ln%)
  520 PRINT "written, new length ";ln%
  530 PRINT
  540 PRINT "reading it back from the module:"
  550 t%=FNcat
  560 PRINT "length now ";blk%!10
  570 PROCload
  580 PROCshow(blk%!10)
  590 PRINT
  600 PRINT "Now CTRL-BREAK. Then *LANMAN and *MOUNT - a hard reset"
  605 PRINT "disconnects the share, so it has to be remounted anyway."
  610 END
  620 :
 1000 DEF FNcat
 1010 blk%!0=nm%
 1020 A%=5:X%=blk% AND 255:Y%=blk% DIV 256
 1030 =USR(&FFDD) AND &FF
 1040 :
 1050 DEF PROCload
 1060 blk%!0=nm%:blk%!2=buf%:blk%!6=0
 1070 A%=&FF:X%=blk% AND 255:Y%=blk% DIV 256
 1080 CALL &FFDD
 1090 ENDPROC
 1100 :
 1110 REM OSFile A=0. +10 is the start of the data and +14 the end; the
 1120 REM module ignores the load and exec addresses, so they go out zero.
 1130 DEF PROCsave(n%)
 1140 blk%!0=nm%:blk%!2=0:blk%!6=0
 1150 blk%!10=buf%:blk%!14=buf%+n%
 1160 A%=0:X%=blk% AND 255:Y%=blk% DIV 256
 1170 CALL &FFDD
 1180 ENDPROC
 1190 :
 1200 REM Byte search, so a second run is a no-op rather than a duplicate.
 1205 REM It does NOT return from inside the loops: "=expr" in an FN exits
 1210 REM at once and leaves every open FOR on the stack.
 1215 DEF FNfind(s$)
 1220 LOCAL i%,j%,ok%,at%
 1225 at%=-1
 1230 FOR i%=0 TO ln%-LEN(s$)
 1235   IF at%>=0 THEN 1290
 1240   ok%=TRUE
 1250   FOR j%=1 TO LEN(s$)
 1260     IF buf%?(i%+j%-1)<>ASC(MID$(s$,j%,1)) THEN ok%=FALSE
 1270   NEXT
 1280   IF ok% THEN at%=i%
 1290 NEXT
 1300 =at%
 1310 :
 1320 DEF PROCshow(n%)
 1330 LOCAL i%,c%
 1340 FOR i%=0 TO n%-1
 1350   c%=buf%?i%
 1360   IF c%=13 THEN PRINT:GOTO 1390
 1370   IF c%>31 AND c%<127 THEN VDU c%:GOTO 1390
 1380   PRINT "<";~c%;">";
 1390 NEXT
 1400 PRINT
 1410 ENDPROC
 1420 :
 1430 REM The way back: NETBAK holds the file exactly as it was.
 1440 DEF PROCrestore
 1450 LOCAL n%
 1460 OSCLI("LOAD "+bk$+" "+STR$~buf%)
 1470 n%=FNlen(bk$)
 1480 PRINT "restoring ";n%;" bytes from ";bk$
 1490 IF n%<1 OR n%>1900 THEN PRINT "bad length - stopping.":ENDPROC
 1500 PROCsave(n%)
 1510 PROCload
 1520 PROCshow(n%)
 1530 PRINT "restored - CTRL-BREAK to apply."
 1540 ENDPROC
 1550 :
 1560 REM Length of a file on the SHARE, via OSFile 5 on that name.
 1570 DEF FNlen(f$)
 1580 LOCAL b%
 1590 $nm%=f$
 1600 blk%!0=nm%
 1610 A%=5:X%=blk% AND 255:Y%=blk% DIV 256
 1620 b%=USR(&FFDD)
 1630 $nm%=nm$
 1640 =blk%!10
 1650 :
 1660 DEF PROCerr
 1670 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1680 REPORT:PRINT
 1690 ENDPROC
