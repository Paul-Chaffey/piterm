   10 REM > RNGSPIKE - can the co-processor get real randomness?
   20 REM
   30 REM   CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "RNGSPIKE"
   40 REM
   50 REM THE ONE UNKNOWN IN docs/ssh.md WITH NO FALLBACK. SSH needs a real
   60 REM CSPRNG for the ephemeral X25519 key and for nonces. BASIC's RND is
   70 REM not one, and a predictable ephemeral key does not fail loudly - it
   80 REM makes a session that works and that a listener can decrypt. So this
   90 REM is answered before any protocol gets written, not after.
  100 REM
  110 REM The Pi's SoC has a hardware RNG at bus 0x7E104000, physical
  120 REM 0x3F104000 on the BCM2837. Whether user code on this core can reach
  130 REM the peripheral window is the entire question, and nobody has tried.
  140 :
  150 REM THIS ONE CAN TAKE THE MACHINE DOWN, unlike ARMSPIKE. It touches a
  160 REM peripheral, in user mode, on a bare-metal core. An unmapped read
  170 REM should hit the core's own data abort handler and report - that is
  180 REM the good failure - but "should" is doing work in that sentence.
  190 REM
  200 REM So the log line goes out BEFORE the call, and RESRAND is closed on
  210 REM every write. If RESRAND ends at "about to CALL", the peripheral
  220 REM read is the answer and no further guessing is needed.
  230 :
  240 REM WHAT THE STAGE MEANS IF IT COMES BACK:
  250 REM
  260 REM   2   it stopped ON the first peripheral read - not mapped for user
  270 REM       mode. Next thing to try is OS_EnterOS and SVC mode, in a
  280 REM       program written not to return.
  290 REM   4   the window is readable but the block never produced a word.
  300 REM       Mapped but not clocked, or the warm-up never completed.
  310 REM   6   it worked. count should be 8.
  320 :
  330 REM Patched by tools/armbuild.sh - do not edit these three by hand, and
  340 REM do not renumber them without updating the sed in that script.
  350 len%=424:REM BUILDSTAMP-LEN
  360 sum%=42591:REM BUILDSTAMP-SUM
  370 bid$="A65F":REM BUILDSTAMP-ID
  380 :
  390 bld$="0828b"
  400 f$="RNGBLOB":log$="RESRAND":logon%=TRUE
  410 base%=&4100000:par%=&4108000
  420 magic%=&5B1CE002
  430 ok%=TRUE
  440 :
  450 IF len%=0 THEN PRINT "Not built. Run tools/armbuild.sh rng first.":END
  460 :
  470 PRINT "RNGSPIKE build ";bld$;"  blob id ";bid$
  480 PRINT "file=";f$;" bytes=";len%;" ref sum=";sum%
  490 PRINT "RNG at &3F104000, user mode, no OS_EnterOS"
  500 PRINT
  510 PROClog("")
  520 PROClog("RNGSPIKE "+bld$+" blob "+bid$+" len "+STR$(len%)+" sum "+STR$(sum%))
  530 :
  540 PRINT "probing &";~base%;" ...";
  550 base%?0=&A5:base%!4=&5A5A5A5A
  560 IF base%?0<>&A5 OR base%!4<>&5A5A5A5A THEN PRINT " NOT WRITABLE":PROClog("FAIL memory not writable"):END
  570 PRINT " writable"
  580 :
  590 base%?0=0:base%?(len%-1)=0
  600 PRINT "loading ";f$;" ...";
  610 OSCLI("LOAD "+f$+" "+STR$~base%)
  620 PRINT " done"
  630 s%=0
  640 FOR i%=0 TO len%-1:s%=s%+base%?i%:NEXT
  650 PRINT "byte sum ";s%;" want ";sum%;
  660 PROClog("byte sum "+STR$(s%)+" want "+STR$(sum%))
  670 IF s%<>sum% THEN PRINT "  ** MISMATCH - NOT CALLING":PROClog("FAIL load corrupt, not calling"):END
  680 PRINT "  ok"
  690 PRINT
  700 :
  710 REM Sentinel the whole block, so an untouched slot is distinguishable
  720 REM from one the blob deliberately zeroed.
  730 FOR i%=0 TO 13:par%!(i%*4)=-1:NEXT
  740 :
  750 REM THE LINE THAT MATTERS. If RESRAND ends here, the peripheral read
  760 REM is what stopped the machine.
  770 PROClog("about to CALL "+FNh(base%)+" - touches &3F104000 in user mode")
  780 PRINT "calling &";~base%;" ..."
  790 n%=USR(base%)
  800 PRINT "returned ";n%
  810 PROClog("returned "+STR$(n%))
  820 :
  830 st%=par%!0:mg%=par%!4:sr%=par%!8:cr%=par%!12
  840 sp%=par%!16:ct%=par%!20
  850 PRINT "stage ";st%;"  magic &";~mg%
  860 PRINT "STATUS &";~sr%;"  CTRL &";~cr%
  870 PRINT "warm-up spins ";sp%;"  words ";ct%
  880 PROClog("stage "+STR$(st%)+" magic "+FNh(mg%)+" STATUS "+FNh(sr%)+" CTRL "+FNh(cr%)+" spins "+STR$(sp%)+" count "+STR$(ct%))
  890 PRINT
  900 :
  910 w$=""
  920 FOR i%=0 TO 7
  930   w$=w$+" "+FNh(par%!(24+i%*4))
  940 NEXT
  950 PRINT "words";w$
  960 PROClog("words"+w$)
  970 PRINT
  980 :
  990 IF mg%<>magic% THEN PRINT "FAIL: magic wrong - that was not our code":ok%=FALSE
 1000 IF st%=2 THEN PRINT "FAIL: stopped on the first peripheral read - not mapped":ok%=FALSE
 1010 IF st%=4 THEN PRINT "FAIL: readable but no words - mapped, not clocked?":ok%=FALSE
 1015 IF ct%>0 AND ct%<8 THEN PRINT "NOTE: only ";ct%;" words - the FIFO ran dry and the wait did not cover it"
 1020 IF st%<>6 THEN PRINT "FAIL: stopped at stage ";st%:ok%=FALSE
 1030 IF ct%<>8 THEN PRINT "FAIL: got ";ct%;" words, wanted 8":ok%=FALSE
 1040 :
 1050 REM Two checks that catch a block returning constants, which is what a
 1060 REM disabled or unclocked RNG looks like from here. Neither is a test
 1070 REM of randomness - that is done on the Linux side from RESRAND - but
 1080 REM both catch the failure that would otherwise look like success.
 1090 z%=0:d%=0
 1100 FOR i%=0 TO 7
 1110   IF par%!(24+i%*4)=0 THEN z%=z%+1
 1120   IF par%!(24+i%*4)=par%!24 THEN d%=d%+1
 1130 NEXT
 1140 IF z%=8 THEN PRINT "FAIL: all eight words are zero":ok%=FALSE
 1150 IF d%=8 THEN PRINT "FAIL: all eight words are identical":ok%=FALSE
 1160 :
 1170 IF ok% THEN PRINT "PASS - the hardware RNG is reachable":PROClog("PASS")
 1180 IF NOT ok% THEN PRINT "FAIL - see above":PROClog("FAIL")
 1190 PRINT
 1200 PRINT "Written to ";log$;". Run it more than once - the words must";
 1210 PRINT " differ between runs."
 1220 END
 1230 :
 1240 REM Appended and CLOSED every line, so a wedge still leaves the log.
 1250 DEF PROClog(s$)
 1260 LOCAL h%,j%
 1270 IF NOT logon% THEN ENDPROC
 1280 h%=OPENUP(log$)
 1290 IF h%=0 THEN h%=OPENOUT(log$)
 1300 IF h%=0 THEN ENDPROC
 1310 PTR#h%=EXT#h%
 1320 FOR j%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,j%,1)):NEXT
 1330 BPUT#h%,13
 1340 CLOSE#h%
 1350 ENDPROC
 1360 :
 1370 DEF FNh(n%)="&"+STR$~n%
