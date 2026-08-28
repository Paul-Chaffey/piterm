   10 REM > FBSAVE - can a program be SAVEd to the share and read back?
   20 REM
   30 REM The last of FBVDU's Phase 0 questions, and the one about the
   40 REM edit-test loop rather than about the machine. FBVDU will be a
   50 REM thousand lines. Typing that in with *EXEC on every run is not
   60 REM an edit-test loop, and 2.3a says protecting that loop is the
   70 REM whole reason the engine is being written in BASIC first.
   80 REM
   90 REM What the workflow needs is: *EXEC once, SAVE, and CHAIN after
  100 REM that. Reading from the share is proven daily - every probe in
  110 REM this project arrives by *EXEC - so the risk is concentrated in
  120 REM SAVE, in whether LANMANFS will take a write of a tokenised
  130 REM program rather than a text file.
  140 REM
  150 REM So: SAVE the running program, read the file back with *LOAD,
  160 REM and compare it word by word against the program still in
  170 REM memory between PAGE and TOP. Byte-identical is the whole
  180 REM round trip - SAVE wrote it, LOAD read it, nothing was
  190 REM translated on the way. A file that comes back byte-identical
  200 REM will CHAIN, and there is a one-line manual confirmation of
  210 REM that at the end for anyone who wants it.
  220 REM
  230 REM NO FRAMEBUFFER, NO MODE CHANGE, BASIC IV SAFE. It runs on the
  240 REM co-processor, on the host, and under the emulator, which is
  250 REM how the logic was checked before it ever reached the Beeb.
  260 :
  270 rf$="RESSAVE"
  280 tf$="FBTEMP"
  290 :
  300 p%=0:t%=0:ln%=0:el%=0:er%=0:ts=0:tl=0:rf%=0:buf%=0
  310 ON ERROR PROCerr:END
  320 PROCopen
  330 PROCw("[fbsave]")
  340 PROCw("run="+STR$(TIME))
  350 :
  360 PRINT "FBSAVE - SAVE and LOAD over the filing system"
  370 PRINT STRING$(46,"-")
  380 :
  390 REM ---- 1: what are we about to write? ---------------------------
  400 REM A BASIC program is exactly the bytes from PAGE to TOP, which is
  410 REM what SAVE writes and what LOAD restores. PAGE goes into a
  420 REM variable first: BBC BASIC will not take a pseudo-variable as
  430 REM the left operand of ? or ! in every position, and fbtest
  440 REM already lost an evening to that shape of error (9.4).
  450 p%=PAGE:t%=TOP:ln%=t%-p%
  460 PRINT "program  PAGE &";~p%;" to TOP &";~t%;"  = ";ln%;" bytes"
  470 PROCw("page=&"+STR$~p%)
  480 PROCw("top=&"+STR$~t%)
  490 PROCw("memlen="+STR$(ln%))
  500 :
  510 REM ---- 2: SAVE it ------------------------------------------------
  520 REM *SAVE through OSCLI rather than the SAVE keyword. BASIC IV
  530 REM treats SAVE as an immediate-mode COMMAND and answers Syntax
  540 REM error when it appears in a program - with a string expression
  550 REM or with a literal, both tried under the emulator 2026-08-20.
  560 REM
  570 REM It is the same OSFILE call underneath, so it tests the same
  580 REM thing about the filing system, and it works on BASIC IV and V
  590 REM alike. The SAVE that a person types at the prompt is not in
  600 REM doubt if this succeeds: it writes the identical bytes by the
  610 REM identical route.
  620 T=TIME
  630 OSCLI("SAVE "+tf$+" "+STR$~p%+" "+STR$~t%)
  640 ts=TIME-T
  650 PRINT "SAVE     ";ts;" cs"
  660 PROCw("save_cs="+STR$(ts))
  670 :
  680 REM ---- 3: what did the filing system actually store? -------------
  690 el%=FNext
  700 PRINT "on disc  ";el%;" bytes";
  710 IF el%=ln% THEN PRINT " - matches" ELSE PRINT " - DIFFERS by ";el%-ln%
  720 PROCw("filelen="+STR$(el%))
  730 IF el%=0 THEN PROCw("fail=nothing was written"):PROCdone:END
  740 :
  750 REM ---- 4: read it back and compare -------------------------------
  760 REM *LOAD to a buffer rather than BGET in a loop: BGET is an OS
  770 REM call per byte and this is 10K or more of them. It also tests
  780 REM the call the workflow will actually use.
  790 DIM buf% ln%+16
  800 T=TIME
  810 OSCLI("LOAD "+tf$+" "+STR$~buf%)
  820 tl=TIME-T
  830 PRINT "LOAD     ";tl;" cs"
  840 PROCw("load_cs="+STR$(tl))
  850 er%=FNdiff
  860 PRINT "compare  ";er%;" differing words of ";ln% DIV 4
  870 PROCw("diffwords="+STR$(er%))
  880 :
  890 PRINT STRING$(46,"-")
  900 IF el%=ln% AND er%=0 THEN PROCpass ELSE PROCfail
  910 PROCdone
  920 END
  930 :
  940 REM ---- the verdict ----------------------------------------------
  950 DEF PROCpass
  960 PROCw("verdict=pass")
  970 PRINT "PASS - the round trip is clean."
  980 PRINT
  990 PRINT "So the loop is: *EXEC once, SAVE ""FBVDU"", then CHAIN"
 1000 PRINT """FBVDU"" on every run after that."
 1010 PRINT
 1020 PRINT "To confirm the interpreter accepts it as well as the bytes"
 1030 PRINT "do, type:   CHAIN """;tf$;""""
 1040 PRINT "It should run this program again from the saved copy."
 1050 ENDPROC
 1060 :
 1070 DEF PROCfail
 1080 PROCw("verdict=fail")
 1090 PRINT "FAIL - do not build the edit-test loop on this."
 1100 PRINT "A length that differs means the filing system translated"
 1110 PRINT "something; differing words mean it corrupted something."
 1120 PRINT "Either way, keep using *EXEC and split the engine so each"
 1130 PRINT "part is small enough to type in (docs/fbvdu.md, risks)."
 1140 ENDPROC
 1150 :
 1160 REM ---- how long is the file? -------------------------------------
 1170 REM EXT# on a channel opened for input, which costs three OS calls
 1180 REM rather than reading the whole thing.
 1190 DEF FNext
 1200 LOCAL f%,n%
 1210 f%=OPENIN(tf$)
 1220 IF f%=0 THEN =0
 1230 n%=EXT#f%
 1240 CLOSE#f%
 1250 =n%
 1260 :
 1270 REM ---- does it match what is still in memory? --------------------
 1280 REM Word at a time. The program is between PAGE and TOP and has not
 1290 REM moved: DIM allocates above TOP, so the buffer cannot have
 1300 REM landed on top of the thing being compared.
 1310 DEF FNdiff
 1320 LOCAL i%,n%
 1330 n%=0
 1340 FOR i%=0 TO ln%-4 STEP 4
 1350   IF buf%!i%<>p%!i% THEN n%=n%+1
 1360 NEXT
 1370 =n%
 1380 :
 1390 REM ---- results file ----------------------------------------------
 1400 DEF PROCopen
 1410 rf%=OPENOUT(rf$)
 1420 IF rf%=0 THEN PRINT "cannot open ";rf$;" - results to screen only"
 1430 ENDPROC
 1440 :
 1450 DEF PROCw(s$)
 1460 LOCAL i%
 1470 IF rf%=0 THEN PRINT s$:ENDPROC
 1480 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1490 BPUT#rf%,13:BPUT#rf%,10
 1500 ENDPROC
 1510 :
 1520 DEF PROCdone
 1530 PROCw("[end]")
 1540 IF rf%<>0 THEN CLOSE#rf%
 1550 rf%=0
 1560 ENDPROC
 1570 :
 1580 DEF PROCerr
 1590 PRINT
 1600 PRINT "Error ";ERR;" at line ";ERL
 1610 REPORT:PRINT
 1620 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 1630 PROCdone
 1640 PRINT "An error at the SAVE is the answer: the share will not take"
 1650 PRINT "a written program, and the engine must stay *EXEC sized."
 1660 ENDPROC
