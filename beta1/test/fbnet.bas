   10 REM > FBNET - read the module's own Choices:Internet.Startup
   20 REM
   30 REM   co-processor OFF, share mounted:
   40 REM       NEW  then  *EXEC FBNET  then  RUN
   50 REM
   60 REM Reads only. Writes nothing to the module.
   70 REM
   80 REM *EDIT and *TYPE both answer "Bad name" on this file, and the
   90 REM module's manual says why: the pseudo file is held in a NON
  100 REM VOLATILE MEMORY CHIP ON THE MODULE, and "LANMANFS will divert a
  110 REM limited subset of OSFile operations (ONLY)" to it. *TYPE opens
  120 REM the file with OSFind and reads it with OSBGet; *EDIT does the
  130 REM same. Neither is diverted, so both are asking the SHARE for a
  140 REM file whose name it cannot even parse.
  150 REM
  160 REM What is diverted, per that section:
  170 REM
  180 REM   A=5   read cat info          - gives the length
  190 REM   A=255 load named file, USING THE GIVEN ADDRESS ONLY - so the
  200 REM         exec address low byte must be zero, since the module
  210 REM         has no load address to offer
  220 REM   A=0   save - replaces the configuration, and each line is
  230 REM         checked to be no more than 80 bytes including the CR
  240 REM
  250 REM So the file is reachable, just not by any command that treats it
  260 REM as a stream. Spec 5.5b-terdecies.
  270 REM
  280 REM The point of reading it: its Hosts section is a name table
  290 REM consulted BEFORE the DNS, and its CIFS section holds the
  300 REM defaults that let *MOUNT be used in shorthand. Both bear on
  310 REM getting the share mounted at power on without typing.
  320 :
  330 nm$="Choices:Internet.Startup"
  340 rf$="RESNET":sf$="RESSTRT"
  350 ON ERROR PROCerr:END
  360 DIM nm% 31,blk% 17,buf% 2047
  370 $nm%=nm$
  380 PRINT "spooling to ";rf$
  390 OSCLI("SPOOL "+rf$)
  400 PRINT "== FBNET =="
  410 PRINT "== FILE == ";nm$
  420 t%=FNcat
  430 PRINT "== TYPE == ";t%;"  (0 = not found, 1 = file)"
  440 IF t%=0 THEN PRINT "== END ==":OSCLI("SPOOL"):PRINT:PRINT "Not found - is LANManFS selected?":END
  450 ln%=blk%!10
  460 PRINT "== LENGTH == ";ln%
  470 IF ln%<1 OR ln%>2047 THEN PRINT "== END ==":OSCLI("SPOOL"):PRINT:PRINT "Length ";ln%;" is not usable - stopping.":END
  480 PROCload
  490 PRINT "== TEXT =="
  500 PROCshow(ln%)
  510 PRINT "== END =="
  520 OSCLI("SPOOL")
  530 REM A byte-exact copy as well as the spooled listing: the spool goes
  540 REM through the VDU and a listing can only ever be a rendering.
  550 OSCLI("SAVE "+sf$+" "+STR$~buf%+" "+STR$~(buf%+ln%))
  560 PRINT
  570 PRINT "FBNET done - ";rf$;" and ";sf$;" are on the share."
  580 END
  590 :
 1000 REM OSFile A=5, read catalogue information. USR so the object type
 1010 REM in A comes back - CALL does not return the registers.
 1020 DEF FNcat
 1030 blk%!0=nm%
 1040 A%=5:X%=blk% AND 255:Y%=blk% DIV 256
 1050 =USR(&FFDD) AND &FF
 1060 :
 1070 REM OSFile A=255. +2 is the address to load at and +6 must be zero
 1080 REM to mean "use it" - the module has no load address of its own.
 1090 DEF PROCload
 1100 blk%!0=nm%
 1110 blk%!2=buf%
 1120 blk%!6=0
 1130 A%=&FF:X%=blk% AND 255:Y%=blk% DIV 256
 1140 CALL &FFDD
 1150 ENDPROC
 1160 :
 1170 REM The file is text, CR terminated, characters 32-126 only. Anything
 1180 REM else is shown as <hex> rather than sent to the VDU, so a stray
 1190 REM byte cannot reformat the screen or corrupt the spool.
 1200 DEF PROCshow(n%)
 1210 LOCAL i%,c%
 1220 FOR i%=0 TO n%-1
 1230   c%=buf%?i%
 1240   IF c%=13 THEN PRINT:GOTO 1270
 1250   IF c%>31 AND c%<127 THEN VDU c%:GOTO 1270
 1260   PRINT "<";~c%;">";
 1270 NEXT
 1280 PRINT
 1290 ENDPROC
 1300 :
 1310 DEF PROCerr
 1320 OSCLI("SPOOL")
 1330 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1340 REPORT:PRINT
 1350 ENDPROC
