   10 REM > ARMSPIKE - does cross-compiled C run on copro 15?
   20 REM
   30 REM   CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "ARMSPIKE"
   40 REM
   50 REM WHY THIS EXISTS. docs/ssh.md makes this the gate on the compressing
   60 REM shim, on an SSH client, and on the purpose-built co-processor core
   70 REM of specification.md 8 Step 3. All three need one thing first: an
   80 REM ARM binary built on the Linux box, loaded here, run, and returning.
   90 REM Nothing else in the project has ever done that. Everything so far
  100 REM is BASIC V, and BASIC V is not going to carry a crypto stack.
  110 REM
  120 REM The blob is ARMBLOB, built by tools/armbuild.sh from src/spike1.c.
  130 REM Different name from this program on purpose: mirror.sh uppercases
  140 REM and truncates to 8, so armspike.bas and the blob would otherwise
  150 REM both land on ARMSPIKE and whichever was written last would win
  160 REM (specification.md 9.0).
  170 :
  180 REM IT WRITES RESSPIKE, and that is not decoration. The first version
  190 REM of this program only PRINTed, so the run of 2026-08-27 left no
  200 REM trace at all and could not be committed as a finding - which is
  210 REM the failure every RES file in this project already exists to
  220 REM prevent. A photograph of a monitor cannot settle what happened.
  230 REM
  240 REM The log is APPENDED and CLOSED on every line, as TUBEDIFF does, so
  250 REM a co-processor that wedges mid-call still leaves its last line on
  260 REM the share. The "about to" lines before each call are there for
  270 REM exactly that: if RESSPIKE ends with one, that call is what hung.
  280 :
  290 REM TWO ARMS, USR and CALL. They differ in what BASIC does with the
  300 REM return, and neither is documented consistently enough to trust:
  310 REM USR is supposed to hand back r0, and whether either passes A% in
  320 REM r0 is a thing the wikis disagree about. So the blob records what
  330 REM it was actually handed and both arms are run with DIFFERENT values,
  340 REM so an answer cannot be a leftover from the other one.
  350 :
  360 REM WHY A FIXED ADDRESS. The blob is not position-independent - -fPIC
  370 REM on ARM wants a GOT and that is more machinery than the thing being
  380 REM tested. So it is LINKED at &4100000 and must be LOADED there. That
  390 REM is 1MB above HIMEM (&4000000, measured in 5.5b-unvicies) and well
  400 REM inside the 200MB of application space the core grants, so nothing
  410 REM else claims it. Whether that address is real is an INFERENCE from
  420 REM copro-armnative.c and not a measurement, so it is probed first.
  430 :
  440 REM WHY NOT *RUN. LANManFS ignores .inf files, so the share cannot
  450 REM carry a load or exec address and *RUN would have nothing to work
  452 REM from - and a .inf on the share arrives as a junk second file whose
  454 REM name truncates. *LOAD with an explicit address avoids all of it.
  456 :
  458 REM Patched by tools/armbuild.sh - do not edit these three by hand, and
  459 REM do not renumber them without updating the sed in that script.
  460 len%=131:REM BUILDSTAMP-LEN
  470 sum%=12624:REM BUILDSTAMP-SUM
  480 bid$="3150":REM BUILDSTAMP-ID
  490 :
  500 bld$="0827b"
  510 f$="ARMBLOB":log$="RESSPIKE":logon%=TRUE
  520 base%=&4100000:par%=&4108000
  530 magic%=&5B1CE001
  540 arg1%=&12345678:in1%=7
  550 arg2%=&0BADCAFE:in2%=20
  560 ok%=TRUE
  570 :
  580 IF len%=0 THEN PRINT "Not built. Run tools/armbuild.sh first.":END
  590 :
  600 PRINT "ARMSPIKE build ";bld$;"  blob id ";bid$
  610 PRINT "file=";f$;" bytes=";len%;" ref sum=";sum%
  620 PRINT "link/load=&";~base%;"  params=&";~par%;"  log=";log$
  630 PRINT
  640 PROClog("")
  650 PROClog("ARMSPIKE "+bld$+" blob "+bid$+" len "+STR$(len%)+" sum "+STR$(sum%))
  660 PROClog("base "+FNh(base%)+" par "+FNh(par%))
  670 :
  680 REM Probe before trusting. Fails with a message rather than as a load
  690 REM that silently went nowhere.
  700 PRINT "probing &";~base%;" ...";
  710 base%?0=&A5:base%!4=&5A5A5A5A
  720 IF base%?0<>&A5 OR base%!4<>&5A5A5A5A THEN PRINT " NOT WRITABLE":PROClog("FAIL memory not writable"):END
  730 PRINT " writable"
  740 PROClog("memory writable")
  750 :
  760 REM Sentinels next, so a short or skipped load cannot checksum clean
  770 REM off whatever was already sitting there. TUBECRC does the same.
  780 base%?0=0:base%?(len%-1)=0
  790 PRINT "loading ";f$;" ...";
  800 OSCLI("LOAD "+f$+" "+STR$~base%)
  810 PRINT " done"
  820 :
  830 s%=0
  840 FOR i%=0 TO len%-1:s%=s%+base%?i%:NEXT
  850 PRINT "byte sum ";s%;" want ";sum%;
  860 PROClog("byte sum "+STR$(s%)+" want "+STR$(sum%))
  870 IF s%<>sum% THEN PRINT "  ** MISMATCH - NOT CALLING":PROClog("FAIL load corrupt, not calling"):END
  880 PRINT "  ok"
  890 PRINT
  900 :
  910 REM ---------------- arm 1: USR ----------------
  920 PROCarm(in1%)
  930 PROClog("about to USR "+FNh(base%)+" A%="+FNh(arg1%)+" in="+STR$(in1%))
  940 PRINT "USR &";~base%;" with A%=&";~arg1%
  950 A%=arg1%
  960 r%=USR(base%)
  970 PRINT "  USR returned &";~r%
  980 PROClog("USR returned "+FNh(r%))
  990 PROCrec("USR",arg1%,in1%)
 1000 IF r%<>in1%*2+1 THEN PRINT "  NOTE: USR did not return the r0 the blob set":PROClog("USR return is NOT r0")
 1010 IF r%=in1%*2+1 THEN PROClog("USR returns r0, confirmed")
 1020 PRINT
 1030 :
 1040 REM ---------------- arm 2: CALL ----------------
 1050 REM Different input and a different A%, so nothing here can be a
 1060 REM leftover from the USR arm still sitting in the parameter block.
 1070 PROCarm(in2%)
 1080 PROClog("about to CALL "+FNh(base%)+" A%="+FNh(arg2%)+" in="+STR$(in2%))
 1090 PRINT "CALL &";~base%;" with A%=&";~arg2%
 1100 A%=arg2%
 1110 CALL base%
 1120 PROCrec("CALL",arg2%,in2%)
 1130 PRINT
 1140 :
 1150 IF ok% THEN PRINT "PASS - compiled C runs on copro 15":PROClog("PASS")
 1160 IF NOT ok% THEN PRINT "FAIL - see above":PROClog("FAIL")
 1170 PRINT
 1180 PRINT "Written to ";log$;" on the share."
 1190 PRINT "Record: release, screen mode, lid on/off, Pi cold or hot."
 1200 END
 1210 :
 1220 REM The out slots get a value the blob would never write, so
 1230 REM "unwritten" and "wrote a zero" are different answers afterwards.
 1240 DEF PROCarm(iv%)
 1250 !par%=iv%
 1260 par%!4=-1:par%!8=-1:par%!12=-1:par%!16=-1
 1270 ENDPROC
 1280 :
 1290 REM Reads the parameter block back and judges it. w$ names the arm so
 1300 REM RESSPIKE says which call each line came from.
 1310 DEF PROCrec(w$,av%,iv%)
 1320 LOCAL st%,mg%,r0%,ov%
 1330 st%=par%!16:mg%=par%!12:r0%=par%!8:ov%=par%!4
 1340 PRINT "  stage ";st%;"  magic &";~mg%;"  r0 &";~r0%;"  out ";ov%
 1350 PROClog(w$+" stage "+STR$(st%)+" magic "+FNh(mg%)+" r0 "+FNh(r0%)+" A% "+FNh(av%)+" in "+STR$(iv%)+" out "+STR$(ov%)+" want "+STR$(iv%*2+1))
 1360 IF mg%<>magic% THEN PRINT "  ";w$;" FAIL: magic wrong - that was not our code":ok%=FALSE
 1370 IF st%<>5 THEN PRINT "  ";w$;" FAIL: stopped at stage ";st%:ok%=FALSE
 1380 IF ov%<>iv%*2+1 THEN PRINT "  ";w$;" FAIL: arithmetic or memory wrong":ok%=FALSE
 1390 IF r0%=av% THEN PRINT "  ";w$;": A% arrives in r0":PROClog(w$+" A% ARRIVES in r0")
 1400 IF r0%<>av% THEN PRINT "  ";w$;": A% does NOT arrive in r0":PROClog(w$+" A% does NOT arrive in r0")
 1410 ENDPROC
 1420 :
 1430 REM Appended and CLOSED every line, so a wedge still leaves the log.
 1440 REM 58ms a BPUT over LANManFS, and this writes a couple of dozen short
 1450 REM lines once, so the cost is a second and it buys the whole record.
 1460 DEF PROClog(s$)
 1470 LOCAL h%,j%
 1480 IF NOT logon% THEN ENDPROC
 1490 h%=OPENUP(log$)
 1500 IF h%=0 THEN h%=OPENOUT(log$)
 1510 IF h%=0 THEN ENDPROC
 1520 PTR#h%=EXT#h%
 1530 FOR j%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,j%,1)):NEXT
 1540 BPUT#h%,13
 1550 CLOSE#h%
 1560 ENDPROC
 1570 :
 1580 DEF FNh(n%)="&"+STR$~n%
