   10 REM > FBPAL2 - is a palette entry above 15 its own entry?
   20 REM
   30 REM FBPAL ran on 2026-08-20 and came back self-contradictory, which
   40 REM was the test's fault and not the reader's. It offered A, B or N
   50 REM as though they were exclusive, and they are not: block A was
   60 REM index 200 and block B was index 8, and 8 is what 200 becomes if
   70 REM VDU 19 wraps mod 16 - so in the wrapped world BOTH blocks
   80 REM change and "A changed" is a true answer that means nothing.
   90 REM
  100 REM The discriminator was never which block changed. It is whether
  110 REM the OTHER one changed TOO:
  120 REM
  130 REM   only 200 changed   256 real entries. xterm-256color is exact.
  140 REM   200 and 8 both     one entry wearing two numbers - 16 entries
  150 REM                      addressed by the low nibble, which is the
  160 REM                      64 colours x 4 tints of 2.3. FNx256 stands.
  170 REM   neither            VDU 19 is ignored above 15. FNx256 stands.
  180 REM
  190 REM A positive control runs FIRST: entry 4 is one 2.3 already proved
  200 REM programmable, so if reprogramming it changes nothing on screen
  210 REM then the method itself is broken and the rest of the run is
  220 REM void. A test that cannot fail its own control is not a test.
  230 REM
  240 REM Two minutes, three questions. ARM NATIVE ONLY - copro 15,
  250 REM *ARMBASIC, *PIVDU 2 before the mode.
  260 :
  270 md%=21
  280 rf$="RESPAL2"
  290 :
  300 fb%=0:sz%=0:pit%=0:stage%=0:rf%=0
  310 ON ERROR PROCerr:END
  320 PROCopen
  330 PROCw("[fbpal2]")
  340 REM A nonce, so two runs are never mistaken for each other and a
  350 REM file left behind by an earlier run cannot be read as this one.
  360 REM TIME is centiseconds since the machine came up, which differs
  370 REM between runs and needs no clock.
  380 PROCw("run="+STR$(TIME))
  390 DIM q% 63,r% 63
  400 :
  410 MODE md%
  420 VDU 23,1,0
  430 PROCvars
  440 IF fb%=0 THEN PROCw("fail=no framebuffer address"):PROCshut:END
  450 :
  460 REM ---- 0: the control -------------------------------------------
  470 REM Entry 4 is in the 16 that 2.3 established are programmable. If
  480 REM this one does not change, nothing below means anything.
  490 stage%=1
  500 PROCtwo(4,5,"index 4","index 5")
  510 PROCsay("CONTROL: entry 4 is known to be programmable")
  520 PRINT "Both blocks are drawn, then entry 4 is asked for yellow."
  530 PROCpause
  540 VDU 19,4,16,255,255,0
  550 PROCask("control","Did the LEFT block turn yellow?","YN")
  560 :
  570 REM ---- 1: VDU 19 on an entry above 15 ---------------------------
  580 stage%=2
  590 PROCtwo(200,8,"index 200","index 8")
  600 PROCsay("TEST 1: entry 200 asked for yellow, via VDU 19")
  610 PRINT "8 is what 200 becomes if VDU 19 wraps mod 16, so watch"
  620 PRINT "BOTH blocks. Whether the RIGHT one moves is the answer."
  630 PROCpause
  640 VDU 19,200,16,255,255,0
  650 PRINT "  1 - only the LEFT block changed"
  660 PRINT "  2 - BOTH blocks changed"
  670 PRINT "  3 - neither changed"
  680 PROCask("vdu19","LEFT only, BOTH, or neither - 1, 2 or 3?","123")
  690 :
  700 REM ---- 2: the same question of OS_Word 12 -----------------------
  710 REM FBPAL recorded osword12=accepted, but accepted only means the
  720 REM SWI returned - OS_ReadPalette returned too, and it is a stub.
  730 REM So ask the screen, and ask it the same way.
  740 stage%=3
  750 PROCtwo(201,9,"index 201","index 9")
  760 PROCsay("TEST 2: entry 201 asked for cyan, via OS_Word 12")
  770 PROCpause
  780 PROCosword(201)
  790 PRINT "  1 - only the LEFT block changed"
  800 PRINT "  2 - BOTH blocks changed"
  810 PRINT "  3 - neither changed"
  820 PROCask("osword12","LEFT only, BOTH, or neither - 1, 2 or 3?","123")
  830 :
  840 VDU 23,1,1
  850 PROCw("[end]")
  860 PROCshut
  870 VDU 26:CLS
  880 PRINT "FBPAL2 done - ";rf$;" is on the share."
  890 END
  900 :
  910 REM ---- two labelled blocks --------------------------------------
  920 REM Big, far apart, and labelled by the driver's own text directly
  930 REM underneath, so there is nothing to count and nothing to line up
  940 REM by eye. FBPAL asked about sixteen 27-pixel bands and got an
  950 REM ambiguous answer; this asks about two blocks 280 pixels wide.
  960 DEF PROCtwo(l%,r2%,a$,b$)
  970 CLS
  980 PROCfill(0,l%)
  990 PROCfill(360,r2%)
 1000 VDU 31,4,26:PRINT "LEFT = ";a$
 1010 VDU 31,45,26:PRINT "RIGHT = ";b$
 1020 ENDPROC
 1030 :
 1040 DEF PROCfill(x%,c%)
 1050 LOCAL row%,i%,a%,w%
 1060 q%?0=c%:q%?1=c%:q%?2=c%:q%?3=c%:w%=!q%
 1070 FOR row%=0 TO 199
 1080   a%=fb%+row%*pit%+x%
 1090   FOR i%=0 TO 276 STEP 4:a%!i%=w%:NEXT
 1100 NEXT
 1110 ENDPROC
 1120 :
 1130 REM ---- OS_Word 12 -----------------------------------------------
 1140 REM ON ERROR LOCAL so an unimplemented SWI is recorded rather than
 1150 REM ending the run with the results file half written.
 1160 DEF PROCosword(n%)
 1170 ON ERROR LOCAL PROCw("osword12call=absent"):ENDPROC
 1180 q%?0=n%:q%?1=16:q%?2=0:q%?3=255:q%?4=255
 1190 SYS "OS_Word",12,q%
 1200 PROCw("osword12call=returned")
 1210 ENDPROC
 1220 :
 1230 REM ---- ask the driver where the screen is -----------------------
 1240 DEF PROCvars
 1250 !q%=148:q%!4=150:q%!8=6:q%!12=-1
 1260 SYS "OS_ReadVduVariables",q%,r%
 1270 fb%=!r%:sz%=r%!4:pit%=r%!8
 1280 PROCw("mode="+STR$(md%))
 1290 PROCw("screen=&"+STR$~fb%)
 1300 PROCw("pitch="+STR$(pit%))
 1310 ENDPROC
 1320 :
 1330 REM ---- results file ---------------------------------------------
 1340 DEF PROCopen
 1350 rf%=OPENOUT(rf$)
 1360 IF rf%=0 THEN PRINT "cannot open ";rf$;" - results to screen only"
 1370 ENDPROC
 1380 :
 1390 DEF PROCw(s$)
 1400 LOCAL i%
 1410 IF rf%=0 THEN PRINT s$:ENDPROC
 1420 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1430 BPUT#rf%,13:BPUT#rf%,10
 1440 ENDPROC
 1450 :
 1460 DEF PROCshut
 1470 IF rf%<>0 THEN CLOSE#rf%
 1480 rf%=0
 1490 ENDPROC
 1500 :
 1510 REM Fold case on LETTERS only - AND &DF mangles digits, and this
 1520 REM probe's answers are all digits (2026-08-20).
 1530 DEF PROCask(k$,p$,v$)
 1540 LOCAL k%,c$
 1550 PRINT p$;" ";
 1560 REPEAT
 1570   k%=GET
 1580   IF k%>96 AND k%<123 THEN k%=k%-32
 1590   c$=CHR$(k%)
 1600 UNTIL INSTR(v$,c$)>0
 1610 VDU k%
 1620 PRINT
 1630 PROCw(k$+"="+c$)
 1640 ENDPROC
 1650 :
 1660 REM ---- screen furniture -----------------------------------------
 1670 REM Text lives below the blocks and never touches column 79: the Pi
 1680 REM driver ignores VDU 23,16 (9.3), so a character in the last
 1690 REM column would scroll the screen.
 1700 DEF PROCsay(s$)
 1710 LOCAL i%
 1720 FOR i%=28 TO 40:VDU 31,0,i%:PRINT SPC(79);:NEXT
 1730 VDU 31,0,28
 1740 PRINT s$
 1750 ENDPROC
 1760 :
 1770 DEF PROCpause
 1780 LOCAL k%
 1790 PRINT "SPACE, then watch the blocks";
 1800 k%=GET
 1810 PRINT
 1820 ENDPROC
 1830 :
 1840 DEF PROCerr
 1850 VDU 26,23,1,1
 1860 PRINT
 1870 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
 1880 REPORT:PRINT
 1890 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
 1900 PROCshut
 1910 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is *PIVDU 2 set?"
 1920 PRINT "Partial results are in ";rf$;" on the share."
 1930 ENDPROC
