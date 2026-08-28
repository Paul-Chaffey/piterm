   10 REM > SSHBEEB - a real SSH handshake, from the BBC Master
   20 REM
   30 REM   CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "SSHBEEB"
   40 REM
   50 REM WHAT THIS IS. The SSH core built by tools/sshbuild.sh, loaded onto
   60 REM copro 15 and driven from BASIC. The core does no I/O at all - this
   70 REM program owns the socket, exactly as PTERM will, and the C only
   80 REM turns ciphertext into plaintext and back.
   90 REM
  100 REM It is NOT the terminal. It runs one command and reads the answer,
  110 REM which is the smallest thing that proves every layer: key exchange,
  120 REM host key, authentication, the channel, and the pty. Wiring it into
  130 REM PTERM is the next step and touches four procedures.
  140 :
  150 REM THE ABI. A% is an opcode, USR returns r0, and arguments live in a
  160 REM parameter block at &4200000. ARMSPIKE proved A% arrives in r0 on
  170 REM this core under both CALL and USR (results/RESSPIKE_0827b), which
  180 REM is why this can be so plain.
  190 REM
  200 REM   1 INIT(compress)     2 AUTH(user,pub,seed)   3 SIZE(cols,rows)
  210 REM   4 INPUT(ptr,len)     5 OUTPUT(ptr,max)       6 READ(ptr,max)
  220 REM   7 WRITE(ptr,len)     8 STATE                 9 ERRPTR
  230 REM  10 VERSION
  240 :
  250 REM THE SEED IS NOT OURS TO SUPPLY. The blob reads the SoC hardware RNG
  260 REM itself (RNGSPIKE proved it reachable from user mode). BASIC's RND
  270 REM must never be anywhere near an ephemeral key: a predictable one
  280 REM does not fail, it produces a session a listener can decrypt.
  290 :
  300 REM Patched by tools/sshbuild.sh - do not edit these by hand.
  310 len%=50244:REM BUILDSTAMP-LEN
  320 sum%=5958089:REM BUILDSTAMP-SUM
  330 bid$="E9C9":REM BUILDSTAMP-ID
  340 :
  350 REM ================ THE FIVE KNOBS - EDIT THESE ================
  360 REM Everything meant to be changed is on the next five lines and
  370 REM nowhere else. Everything from line 640 on is machinery.
  380 :
  390 host$="192.0.2.10":port%=22:user$="user"
  400 comp%=1
  410 work$="for i in 1 2 3 4 5 6 7 8 9 10; do clear; ls -la /usr/bin | head -60; done"
  420 show%=FALSE
  430 logon%=TRUE
  440 :
  450 REM comp%   1 asks for zlib server-to-client, 0 does not. Run it both
  460 REM         ways for the A/B: the ratio is the point of the exercise.
  470 REM         work$ above is ~10s of module uncompressed, ~1.3s with
  480 REM         zlib. Measured on Linux: 44,178 wire against 5,382.
  490 REM work$   TEN REDRAWS, not one long listing. It is what a
  500 REM         full-screen program actually does, it is where deflate's
  510 REM         32KB window pays, and both legs finish in seconds. The
  520 REM         full /usr/bin listing was 223KB - fine compressed at 20s,
  530 REM         but one to two minutes uncompressed, which is a long time
  540 REM         to watch a machine that gave no sign of being alive.
  550 REM show%   TRUE prints what arrives. OFF for a measurement: SSHBEEB
  560 REM         does not route output to the Pi, so every VDU crosses the
  570 REM         Tube to the HOST's screen and 223KB would be timed against
  580 REM         the BBC's VDU driver rather than the module. 5.5b-unvicies
  590 REM         also found heavy R1 traffic in MODE 0 freezes the copro.
  600 REM         TRUE only for a short workload, in MODE 7.
  610 REM logon%  writes RESSPIKE-style progress to RESSSH on the share.
  620 REM ==============================================================
  630 :
  640 bld$="0828c"
  650 f$="SSHBLOB":k$="SSHKEY":log$="RESSSH"
  660 base%=&4100000:par%=&4200000
  670 cmd$=work$+"; echo SSHOK-$((6*7))"+CHR$(10)
  680 AFINET%=2:SOCKSTREAM%=1:mnowait%=8
  690 ver%=&5B1CE003
  700 :
  710 IF len%=0 THEN PRINT "Not built. Run tools/sshbuild.sh first.":END
  720 :
  730 DIM blk% 31,sa% 31,io% 4095,key% 79,nm% 63
  740 :
  750 PRINT "SSHBEEB ";bld$;"  blob ";bid$;"  ";len%;" bytes"
  760 PRINT "to ";host$;":";port%;" as ";user$;
  770 IF comp% THEN PRINT "  (asking for zlib)" ELSE PRINT
  780 PROClog("")
  790 PROClog("SSHBEEB "+bld$+" blob "+bid$+" len "+STR$(len%)+" sum "+STR$(sum%))
  800 PROClog("host "+host$+" port "+STR$(port%)+" user "+user$+" comp "+STR$(comp%))
  810 :
  820 REM ---- load and verify the blob ----
  830 base%?0=0:base%?(len%-1)=0
  840 PRINT "loading ";f$;
  850 OSCLI("LOAD "+f$+" "+STR$~base%)
  860 s%=0
  870 FOR i%=0 TO len%-1:s%=s%+base%?i%:NEXT
  880 PRINT "  sum ";s%;
  890 PROClog("blob sum "+STR$(s%)+" want "+STR$(sum%))
  900 IF s%<>sum% THEN PRINT " ** MISMATCH":PROClog("FAIL blob corrupt"):END
  910 PRINT "  ok"
  920 :
  930 REM 48KB across the Tube is where a dropped byte would show, and 5.5g
  940 REM measured one lost per 874,000 before the capacitor went in. The sum
  950 REM above is the guard: a blob one byte short is not a program.
  960 :
  970 OSCLI("LOAD "+k$+" "+STR$~key%)
  980 PRINT "key loaded"
  990 :
 1000 A%=10:v%=USR(base%)
 1010 PRINT "blob version &";~v%;
 1020 IF v%<>ver% THEN PRINT " ** WRONG BLOB":PROClog("FAIL blob version"):END
 1030 PRINT "  ok"
 1040 :
 1050 REM ---- start the core ----
 1060 par%!4=comp%
 1070 A%=1:r%=USR(base%)
 1080 IF r%<>0 THEN PRINT "INIT failed - no entropy from the RNG":PROClog("FAIL no entropy"):END
 1090 PROClog("init ok, seeded from the SoC RNG")
 1100 :
 1110 REM NOT $nm%=user$ - BBC BASIC's $ appends CR, and the blob would send
 1120 REM a user name with a carriage return on the end. The blob now strips
 1130 REM one as well, so this is belt and braces, but the explicit form is
 1140 REM what should be read here.
 1150 PROCstr(nm%,user$)
 1160 par%!4=nm%:par%!8=key%:par%!12=key%+32
 1170 A%=2:r%=USR(base%)
 1180 IF r%<>0 THEN PROCbad("AUTH"):END
 1190 par%!4=80:par%!8=64
 1200 A%=3:r%=USR(base%)
 1210 :
 1220 REM ---- the socket is ours, not the core's ----
 1230 PROCzero:blk%?2=&00
 1240 blk%!4=AFINET%:blk%!8=SOCKSTREAM%:blk%!12=0
 1250 PROCosw:PROCchk("create")
 1260 sock%=blk%!4
 1270 PROCsa
 1280 PROCzero:blk%?2=&04
 1290 blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1300 PROCosw:PROCchk("connect")
 1310 PRINT "connected"
 1320 PROClog("connected")
 1330 :
 1340 REM ---- the pump: the same shape PTERM's will be ----
 1350 t0%=TIME:st%=-1:sent%=FALSE:done%=FALSE:wire%=0:app%=0
 1360 REM Counted again from the moment the shell opens. The totals include
 1370 REM the handshake - about 1,400 bytes of KEXINIT, host key and
 1380 REM signature - which on a one-line command swamps everything and made
 1390 REM the first hardware run look as though compression had TRIPLED the
 1400 REM traffic. The ratio that means anything is the one after OPEN.
 1410 wire0%=0:app0%=0:t9%=0:tp%=TIME
 1420 REPEAT
 1430   PROCdrain
 1440   n%=FNrecv
 1450   IF n%>0 THEN wire%=wire%+n%:PROCfeed(n%)
 1460   PROCshow
 1470   A%=8:s2%=USR(base%)
 1480   IF s2%<>st% THEN st%=s2%:PROCsay(st%)
 1490   IF st%=9 AND t9%=0 THEN wire0%=wire%:app0%=app%:t9%=TIME
 1500 IF (TIME-tp%)>500 THEN PROCprog:tp%=TIME
 1510   IF st%=9 AND NOT sent% THEN PROCsend(cmd$):sent%=TRUE
 1520 UNTIL done% OR st%=10 OR st%=11 OR st%=12 OR (TIME-t0%)>30000
 1530 :
 1540 PROCdrain
 1550 PRINT
 1560 IF st%=10 THEN PROCbad("session")
 1570 PROClog("total wire "+STR$(wire%)+" app "+STR$(app%))
 1580 w2%=wire%-wire0%:a2%=app%-app0%
 1590 PROClog("session wire "+STR$(w2%)+" app "+STR$(a2%)+" comp "+STR$(comp%))
 1600 IF a2%>0 THEN PROClog("session ratio "+STR$(INT(w2%*1000/a2%)/1000))
 1610 IF t9%>0 THEN PROClog("session cs "+STR$(TIME-t9%))
 1620 IF t9%>0 THEN PRINT "handshake ";wire0%;" bytes to OPEN in ";t9%-t0%;"cs"
 1630 PRINT "session   ";w2%;" wire  ";a2%;" screen"
 1640 IF a2%>0 THEN PRINT "ratio     ";INT(w2%*1000/a2%)/1000
 1650 IF done% THEN PRINT "PASS - a shell answered":PROClog("PASS")
 1660 IF NOT done% THEN PRINT "INCOMPLETE at state ";st%:PROClog("INCOMPLETE state "+STR$(st%))
 1670 :
 1680 PROCzero:blk%?2=&10:blk%!4=sock%:PROCosw
 1690 END
 1700 :
 1710 REM ---- helpers ----
 1720 :
 1730 REM Everything the core wants to send, out through the module.
 1740 DEF PROCdrain
 1750 LOCAL n%,s%,g%,t%
 1760 REPEAT
 1770   par%!4=io%:par%!8=1024
 1780   A%=5:n%=USR(base%)
 1790   IF n%>0 THEN PROCraw(n%)
 1800 UNTIL n%=0
 1810 ENDPROC
 1820 :
 1830 REM A send can be refused; PTERM learned to bound the retries rather
 1840 REM than spin, because at 3.28ms a call two hundred tries is two thirds
 1850 REM of a second with nothing able to interrupt it.
 1860 DEF PROCraw(n%)
 1870 LOCAL s%,g%,t%
 1880 s%=0:t%=0
 1890 REPEAT
 1900   PROCzero:blk%?2=&08
 1910   blk%!4=sock%:blk%!8=io%+s%:blk%!12=n%-s%:blk%!16=mnowait%
 1920   PROCosw
 1930   g%=0
 1940   IF blk%?3=0 THEN g%=blk%!4
 1950   IF g%>0 THEN s%=s%+g%
 1960   IF g%<1 THEN t%=t%+1
 1970 UNTIL s%>=n% OR t%>30
 1980 ENDPROC
 1990 :
 2000 REM 64 and never more. 5.5c measured reads above that refused - AND the
 2010 REM refusal consumes what it refuses. Under telnet that lost 111 bytes
 2020 REM and printed an escape sequence as text; under SSH it is a Poly1305
 2030 REM failure and a dead session.
 2040 DEF FNrecv
 2050 LOCAL g%
 2060 PROCzero:blk%?2=&05
 2070 blk%!4=sock%:blk%!8=io%:blk%!12=64:blk%!16=mnowait%
 2080 PROCosw
 2090 IF blk%?2<>0 THEN =0
 2100 IF blk%?3<>0 THEN =0
 2110 g%=blk%!4
 2120 IF g%<1 THEN =0
 2130 IF g%>64 THEN =0
 2140 =g%
 2150 :
 2160 DEF PROCfeed(n%)
 2170 LOCAL r%
 2180 par%!4=io%:par%!8=n%
 2190 A%=4:r%=USR(base%)
 2200 ENDPROC
 2210 :
 2220 REM Plaintext out of the core and onto the screen. PTERM will hand
 2230 REM these bytes to PROCv_write instead of PRINT.
 2240 DEF PROCshow
 2250 LOCAL n%
 2260 REPEAT
 2270   par%!4=io%:par%!8=1024
 2280   A%=6:n%=USR(base%)
 2290   IF n%>0 THEN PROCemit(n%)
 2300 UNTIL n%=0
 2310 ENDPROC
 2320 :
 2330 REM CALLED ONLY WITH n%>0, because a BBC FOR ALWAYS RUNS ONCE: at n%=0
 2340 REM the loop below would run with i%=0 and print a stale byte left in
 2350 REM io% by the previous pass. pterm.bas's PROCemit carries the same
 2360 REM guard for the same reason, and it was nearly forgotten again here.
 2370 DEF PROCemit(n%)
 2380 LOCAL i%,c%
 2390 app%=app%+n%
 2400 IF show% THEN FOR i%=0 TO n%-1:PROCvdu(io%?i%):NEXT
 2410 PROCmark(n%)
 2420 ENDPROC
 2430 :
 2440 DEF PROCvdu(c%)
 2450 IF c%>=32 AND c%<127 THEN VDU c%
 2460 IF c%=10 OR c%=13 THEN VDU c%
 2470 ENDPROC
 2480 DEF PROCmark(n%)
 2490 LOCAL i%
 2500 REM NESTED IFs, NOT AND. BBC BASIC's AND DOES NOT SHORT-CIRCUIT, so
 2510 REM the previous form did five array reads for every byte of the
 2520 REM stream - 223KB of listing meant over a million interpreted reads,
 2530 REM and the scan, not the module, was what set the run's duration.
 2540 REM Nested IFs stop at the first mismatch, which for a directory
 2550 REM listing is almost always the first one.
 2560 IF n%<8 THEN ENDPROC
 2570 FOR i%=0 TO n%-8
 2580   IF io%?i%=83 THEN IF io%?(i%+1)=83 THEN IF io%?(i%+2)=72 THEN IF io%?(i%+6)=52 THEN IF io%?(i%+7)=50 THEN done%=TRUE
 2590 NEXT
 2600 ENDPROC
 2610 :
 2620 DEF PROCsend(s$)
 2630 LOCAL i%,r%
 2640 FOR i%=1 TO LEN(s$):io%?(i%-1)=ASC(MID$(s$,i%,1)):NEXT
 2650 par%!4=io%:par%!8=LEN(s$)
 2660 A%=7:r%=USR(base%)
 2670 PROClog("sent the command, r="+STR$(r%))
 2680 ENDPROC
 2690 :
 2700 DEF PROCsay(n%)
 2710 LOCAL s$
 2720 s$="?"
 2730 IF n%=0 THEN s$="version"
 2740 IF n%=1 THEN s$="kexinit"
 2750 IF n%=2 THEN s$="kex reply"
 2760 IF n%=3 THEN s$="newkeys"
 2770 IF n%=4 THEN s$="service"
 2780 IF n%=5 THEN s$="auth"
 2790 IF n%=6 THEN s$="channel"
 2800 IF n%=7 THEN s$="pty"
 2810 IF n%=8 THEN s$="shell"
 2820 IF n%=9 THEN s$="OPEN"
 2830 IF n%=10 THEN s$="ERROR"
 2840 PROClog("state "+STR$(n%)+" "+s$+" at "+STR$(TIME-t0%)+"cs")
 2850 ENDPROC
 2860 :
 2870 DEF PROCbad(w$)
 2880 LOCAL p%,e$,c%
 2890 A%=9:p%=USR(base%)
 2900 e$=""
 2910 REPEAT
 2920   c%=p%?LEN(e$)
 2930   IF c%>0 THEN e$=e$+CHR$(c%)
 2940 UNTIL c%=0 OR LEN(e$)>90
 2950 PRINT w$;" FAILED: ";e$
 2960 PROClog("FAIL "+w$+": "+e$)
 2970 ENDPROC
 2980 :
 2990 DEF PROCsa
 3000 LOCAL i%,a%,b%,o%
 3010 FOR i%=0 TO 15:sa%?i%=0:NEXT
 3020 sa%?0=16:sa%?1=AFINET%
 3030 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 3040 a%=1:o%=4
 3050 FOR i%=1 TO 4
 3060   b%=INSTR(host$+".",".",a%)
 3070   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 3080   a%=b%+1:o%=o%+1
 3090 NEXT
 3100 ENDPROC
 3110 :
 3120 DEF PROCzero
 3130 LOCAL i%
 3140 FOR i%=0 TO 27:blk%?i%=0:NEXT
 3150 blk%?0=28:blk%?1=28:blk%?3=0
 3160 ENDPROC
 3170 :
 3180 DEF PROCosw
 3190 SYS "OS_Word",&C0,blk%
 3200 ENDPROC
 3210 :
 3220 REM A surviving +2 means nothing claimed the call, and then no field is
 3230 REM touched at all - so +3 reads 0 because it started 0, and an
 3240 REM unclaimed call is indistinguishable from success (5.5c).
 3250 DEF PROCchk(w$)
 3260 IF blk%?2<>0 THEN PRINT "no socket module (";w$;")":PROClog("FAIL no module"):END
 3270 IF blk%?3<>0 THEN PRINT "cannot ";w$;", r=&";~blk%?3:PROClog("FAIL "+w$):END
 3280 ENDPROC
 3290 :
 3300 REM A SLOW RUN MUST NOT LOOK LIKE A WEDGED ONE. The uncompressed leg was
 3310 REM stopped by hand on 2026-08-28 because a minute of silence is
 3320 REM indistinguishable from the lockup of an hour earlier. One dot every
 3330 REM five seconds costs nothing even in MODE 0, and the log line gives the
 3340 REM rate afterwards.
 3350 DEF PROCprog
 3360 VDU 46
 3370 PROClog("progress wire "+STR$(wire%)+" app "+STR$(app%)+" at "+STR$(TIME-t0%)+"cs")
 3380 ENDPROC
 3390 :
 3400 DEF PROCstr(p%,s$)
 3410 LOCAL i%
 3420 FOR i%=1 TO LEN(s$):p%?(i%-1)=ASC(MID$(s$,i%,1)):NEXT
 3430 p%?LEN(s$)=0
 3440 ENDPROC
 3450 :
 3460 DEF PROClog(s$)
 3470 LOCAL h%,j%
 3480 IF NOT logon% THEN ENDPROC
 3490 h%=OPENUP(log$)
 3500 IF h%=0 THEN h%=OPENOUT(log$)
 3510 IF h%=0 THEN ENDPROC
 3520 PTR#h%=EXT#h%
 3530 FOR j%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,j%,1)):NEXT
 3540 BPUT#h%,13
 3550 CLOSE#h%
 3560 ENDPROC
