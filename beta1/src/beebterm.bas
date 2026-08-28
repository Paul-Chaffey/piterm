   10 REM > BEEBTERM - network terminal client
   20 REM
   30 REM Talks OSWORD &C0 directly, and runs in either place: on the
   40 REM BBC Master host, or on the ARM co-processor (copro 15, reached
   50 REM with *ARMBASIC). BEEBNET is cancelled - 5.5c established that
   60 REM pointers cross the Tube, so the co-processor calls the module
   70 REM itself and there is no host-side ROM to talk to. 8 Step 2.
   80 REM
   90 REM Developed against SOCKSTUB, whose conventions are GUESSES.
  100 REM Passing there does not prove it works on real hardware.
  110 :
  120 REM ---------------- configuration ----------------
  130 REM The Linux box on the LAN, running the socat shim from 3.5.
  140 REM Dotted quad only - Resolver_GetHostByName is not wired up.
  150 host$="192.0.2.10"
  160 port%=2323
  170 REM mode%=21 is the Pi framebuffer's 640x512 256-colour mode and
  180 REM exists only on the co-processor with the Pi VDU driver live
  190 REM (2.3). Use mode%=3 on the host or under the emulator.
  200 REM vdu% picks HOW output reaches the Pi framebuffer, and it
  210 REM differs by core (2.3): 1 = *PIVDU, native ARM only. 2 = CALL
  220 REM &300, the 6502 co-processors, which have no *PIVDU at all.
  230 REM 0 = leave output alone, for the host and the emulator.
  240 REM Using 1 on a 6502 co-pro gives Bad command, error 254.
  250 REM pivdu% is the *PIVDU argument: 2 = Pi only, 3 = both screens.
  260 mode%=21
  270 vdu%=0
  280 pivdu%=2
  290 REM Idle exit, centiseconds. 0 = never. Non-zero only so that
  300 REM automated emulator tests terminate; a real terminal wants 0.
  310 idle%=0
  320 quitkey%=29
  330 REM drain%: bytes taken before returning to the main loop.
  340 REM keyev%: bytes between keyboard polls DURING a drain - the one
  350 REM that decides how fast CTRL-] or q is felt when a full-screen
  360 REM program is repainting continuously.
  370 drain%=1024:keyev%=256
  380 REM Offline replay. replay$ non-empty reads a captured byte
  390 REM stream from a file instead of the socket, so the parser and
  400 REM renderer can be exercised in the emulator with no module.
  410 REM dump% then walks the finished screen with OSBYTE 135 and
  420 REM prints it, which is how a rendering fault is seen without
  430 REM photographing a monitor. Capture with tools/ptycap.py.
  440 replay$="":dump%=FALSE:fh%=0
  441 probe%=FALSE:wrap%=FALSE
  442 fg%=7:bg%=0:bold%=FALSE:rev%=FALSE
  450 DIM d$(99)
  460 :
  470 AFINET%=2:SOCKSTREAM%=1
  480 FIONBIO%=&8004667E
  490 DIM blk% 31,sa% 31,rx% 1023,tx% 15
  500 REM 128 IS A HARD CEILING - do not raise it. Measured 2026-08-19
  510 REM with rmax%=512: largest successful read stayed at 128, every
  520 REM request above it failed, AND data was lost at exactly the
  530 REM points the ramp reached 256 and 512. So an oversized request
  540 REM does not merely fail, it discards what was buffered. The
  550 REM same test at 128 loses nothing.
  560 rmax%=128:rsz%=1
  570 DIM p%(7)
  580 :
  590 ON ERROR PROCfail:END
  600 REM Before MODE: mode 21 does not exist until output is routed to
  610 REM the Pi, and the host MOS would refuse it.
  620 IF dump% THEN VDU 3
  630 PROCvdu
  640 MODE mode%
  650 quit%=FALSE:tstate%=0:vstate%=0:np%=0:priv%=FALSE
  660 PROCgeom
  670 sct%=1:scb%=rows%:svx%=0:svy%=0:alt%=FALSE
  680 REM Scroll protection. Bit 0 of the cursor-movement flags makes
  690 REM the cursor going off the right edge generate a PENDING
  700 REM newline instead of scrolling at once - the BBC Master's
  710 REM equivalent of VT deferred wrap. Without it every character
  720 REM written in the last column scrolls the screen, which no
  730 REM full-screen program survives. x=1,y=254 sets bit 0 and
  740 REM leaves the other flags alone.
  750 VDU 23,16,1,254,0,0,0,0,0,0
  755 PROCpal
  760 PRINT "BEEBTERM -> ";host$;":";port%;"  CTRL-] quits"
  761 IF probe% THEN PROCprobe
  770 :
  780 PROCnet_open
  790 *FX4,1
  800 *FX229,1
  810 last%=TIME
  820 REPEAT
  830   PROCpump
  840   PROCkeys
  850   IF idle%>0 AND (TIME-last%)>idle% THEN quit%=TRUE
  860 UNTIL quit%
  870 PROCtidy
  880 IF dump% THEN PROCdump
  890 PROCnet_close
  900 PRINT
  910 PRINT "BEEBTERM ended."
  920 END
  930 :
  940 REM ================ receive and dispatch ================
  950 REM Drain until the socket is empty, rather than taking one read
  960 REM per pass round the main loop. Every pass also calls PROCkeys,
  970 REM and on a co-processor INKEY is an OSBYTE across the Tube - so
  980 REM one read per pass paid a keyboard round trip for every 128
  990 REM bytes. During a burst that halves throughput and makes the
 1000 REM output arrive in visible steps. drain% caps how much is taken
 1010 REM before the keyboard is looked at, so CTRL-] still answers
 1020 REM while a long listing is coming in.
 1030 DEF PROCpump
 1040 LOCAL n%,t%,kp%
 1050 t%=0:kp%=0
 1060 REPEAT
 1070   n%=FNnet_recv
 1080   IF n%>0 THEN PROCemit(n%)
 1090   t%=t%+n%
 1100   REM Look at the keyboard DURING the drain, not only between
 1110   REM drains. While top is repainting the socket is never empty,
 1120   REM so waiting for the loop to end meant a keypress waited for
 1130   REM the whole backlog. Sending q at once stops the far end even
 1140   REM though the backlog still has to be rendered.
 1150   IF t%-kp%>=keyev% THEN PROCkeys:kp%=t%
 1160 UNTIL n%<1 OR t%>drain% OR quit%
 1170 ENDPROC
 1180 REM Guarded: a BBC FOR always runs once, so 0 TO -1 would
 1190 REM read a byte that was never received (9.4).
 1200 DEF PROCemit(n%)
 1210 LOCAL i%
 1220 last%=TIME
 1230 FOR i%=0 TO n%-1
 1240   PROCbyte(rx%?i%)
 1250 NEXT
 1260 ENDPROC
 1270 :
 1280 DEF PROCbyte(c%)
 1290 IF tstate%>0 THEN PROCtelnet(c%):ENDPROC
 1300 IF c%=255 THEN tstate%=1:ENDPROC
 1310 PROCvt(c%)
 1320 ENDPROC
 1330 :
 1340 REM ================ telnet IAC ================
 1350 REM Refuse every option except server echo and suppress-go-ahead,
 1360 REM which are what make a line-mode host usable.
 1370 DEF PROCtelnet(c%)
 1380 IF tstate%=1 THEN PROCiac(c%):ENDPROC
 1390 IF tstate%=2 THEN PROCiacopt(c%):ENDPROC
 1400 IF tstate%=3 THEN IF c%=255 THEN tstate%=4
 1410 IF tstate%=4 THEN IF c%=240 THEN tstate%=0 ELSE tstate%=3
 1420 ENDPROC
 1430 :
 1440 DEF PROCiac(c%)
 1450 IF c%=255 THEN tstate%=0:PROCvt(255):ENDPROC
 1460 IF c%=250 THEN tstate%=3:ENDPROC
 1470 IF c%>=251 AND c%<=254 THEN tverb%=c%:tstate%=2:ENDPROC
 1480 tstate%=0
 1490 ENDPROC
 1500 :
 1510 DEF PROCiacopt(o%)
 1520 LOCAL r%
 1530 tstate%=0
 1540 REM 251=WILL 252=WONT 253=DO 254=DONT ; 1=ECHO 3=SGA
 1550 IF tverb%=251 THEN r%=254:IF o%=1 OR o%=3 THEN r%=253
 1560 IF tverb%=253 THEN r%=252
 1570 IF tverb%=252 OR tverb%=254 THEN ENDPROC
 1580 tx%?0=255:tx%?1=r%:tx%?2=o%
 1590 PROCnet_send(3)
 1600 ENDPROC
 1610 :
 1620 REM ================ VT / ANSI ================
 1630 DEF PROCvt(c%)
 1640 IF vstate%=1 THEN PROCesc(c%):ENDPROC
 1650 IF vstate%=2 THEN PROCcsi(c%):ENDPROC
 1660 IF vstate%=3 THEN PROCosc(c%):ENDPROC
 1670 IF vstate%=4 THEN vstate%=0:ENDPROC
 1680 IF vstate%=5 THEN vstate%=0:ENDPROC
 1690 IF c%=27 THEN vstate%=1:ENDPROC
 1691 REM DEFERRED WRAP, in software. A VT filling the last column
 1692 REM leaves the cursor pending and only moves on the NEXT
 1693 REM character; the BBC wraps at once. So a full-width line is
 1694 REM already on the next row by the time the host's CR LF
 1695 REM arrives, and the LF costs a second row - the line overflow
 1696 REM and apparent double spacing seen on hardware. Swallowing
 1697 REM exactly one LF after a wrap restores VT behaviour and gets
 1698 REM the 80th column back, so the far end can be told 80.
 1699 IF c%=10 AND wrap% THEN wrap%=FALSE:ENDPROC
 1700 IF c%=13 THEN VDU 13:ENDPROC
 1701 IF c%=10 OR c%=8 OR c%=7 OR c%=9 THEN wrap%=FALSE:VDU c%:ENDPROC
 1710 IF c%>31 AND c%<127 THEN PROCput(c%):ENDPROC
 1711 ENDPROC
 1712 :
 1713 REM The bottom-right cell cannot be written without scrolling.
 1714 REM Deferring the LF is not enough: the BBC performs the WRAP
 1715 REM itself, at once, and on the bottom row a wrap IS a scroll.
 1716 REM Measured against a real 64x80 top capture - every frame ends
 1717 REM with a full-width bottom line, so the display marched up one
 1718 REM row per refresh. A VT sets pending-wrap there and scrolls
 1719 REM nothing, because top repositions with ESC[H for the next
 1720 REM frame. Dropping that one character costs the bottom-right
 1721 REM cell, which full-screen programs pad with a space anyway.
 1722 DEF PROCput(c%)
 1723 IF POS=cols%-1 AND VPOS=scb%-sct% THEN ENDPROC
 1724 VDU c%:wrap%=(POS=0)
 1725 ENDPROC
 1730 :
 1740 DEF PROCesc(c%)
 1750 vstate%=0
 1760 IF c%=91 THEN np%=0:p%(0)=0:p%(1)=0:priv%=FALSE:vstate%=2:ENDPROC
 1770 REM ESC 7 / ESC 8 - save and restore the cursor. Full-screen
 1780 REM programs bracket their repaints with these.
 1790 IF c%=55 THEN PROCsave:ENDPROC
 1800 IF c%=56 THEN PROCrest:ENDPROC
 1810 REM The five STRING sequences, all introduced by one byte after
 1820 REM ESC and all running until BEL or ST: OSC ] , DCS P , SOS X ,
 1830 REM PM ^ and APC _ . Only OSC was handled, so a shell emitting
 1840 REM its integration string with any of the others had the whole
 1850 REM payload printed - "3008;start=...;user=user;pid=...;cwd=..."
 1860 REM on hardware 2026-08-19. Bash also sets the window title with
 1870 REM OSC on every prompt.
 1880 IF c%=93 OR c%=80 OR c%=88 OR c%=94 OR c%=95 THEN vstate%=3:ENDPROC
 1890 REM ESC ( ) * + and ESC # each take one more byte. Consume it,
 1900 REM or the character after lands on the screen: ESC ( B prints B.
 1910 IF c%>39 AND c%<44 THEN vstate%=5:ENDPROC
 1920 IF c%=35 THEN vstate%=5:ENDPROC
 1930 REM Everything else after ESC is a one-byte form and is already
 1940 REM consumed by having got here.
 1950 ENDPROC
 1960 :
 1970 REM vstate%=3 in the string, 4 after an ESC inside it: the string
 1980 REM ends at BEL or at ESC \ , and 4 eats whichever byte follows.
 1990 DEF PROCosc(c%)
 2000 IF c%=7 THEN vstate%=0:ENDPROC
 2010 IF c%=27 THEN vstate%=4
 2020 ENDPROC
 2030 :
 2040 DEF PROCcsi(c%)
 2050 IF c%>47 AND c%<58 THEN p%(np%)=p%(np%)*10+c%-48:ENDPROC
 2060 IF c%=59 THEN IF np%<7 THEN np%=np%+1:p%(np%)=0:ENDPROC
 2070 IF c%=63 THEN priv%=TRUE:ENDPROC
 2080 vstate%=0
 2090 PROCdo(c%)
 2100 ENDPROC
 2110 :
 2120 DEF PROCdo(c%)
 2130 LOCAL n%
 2140 n%=p%(0):IF n%<1 THEN n%=1
 2150 IF c%=72 OR c%=102 THEN PROCgoto:ENDPROC
 2160 IF c%=65 THEN PROCrep(11,n%):ENDPROC
 2170 IF c%=66 THEN PROCrep(10,n%):ENDPROC
 2180 IF c%=67 THEN PROCrep(9,n%):ENDPROC
 2190 IF c%=68 THEN PROCrep(8,n%):ENDPROC
 2200 IF c%=74 THEN PROCerase:ENDPROC
 2210 IF c%=75 THEN PROCeol:ENDPROC
 2220 IF c%=114 THEN PROCregion:ENDPROC
 2230 IF c%=115 THEN PROCsave:ENDPROC
 2240 IF c%=117 THEN PROCrest:ENDPROC
 2250 IF c%=104 AND priv% THEN PROCpriv(TRUE):ENDPROC
 2260 IF c%=108 AND priv% THEN PROCpriv(FALSE):ENDPROC
 2265 IF c%=109 THEN PROCsgr:ENDPROC
 2270 REM SGR and anything else are still ignored - colour needs the
 2280 REM palette mapping pinned down on hardware first (2.3).
 2290 ENDPROC
 2300 :
 2310 DEF PROCgoto
 2320 LOCAL r%,k%
 2330 r%=p%(0):IF r%<1 THEN r%=1
 2340 k%=p%(1):IF k%<1 THEN k%=1
 2350 REM ANSI counts rows from the top of the SCREEN. Inside a BBC
 2360 REM text window VDU 31 counts from the top of the WINDOW, so
 2370 REM subtract the region origin and clamp to the window.
 2380 r%=r%-sct%+1
 2390 IF r%<1 THEN r%=1
 2400 IF r%>scb%-sct%+1 THEN r%=scb%-sct%+1
 2410 IF k%>cols% THEN k%=cols%
 2420 VDU 31,k%-1,r%-1
 2430 ENDPROC
 2440 :
 2450 DEF PROCrep(v%,n%)
 2460 LOCAL i%
 2470 IF n%<1 THEN ENDPROC
 2480 FOR i%=1 TO n%:VDU v%:NEXT
 2490 ENDPROC
 2500 :
 2510 REM ED. 2 is the whole screen, 0 is cursor to the end of it and
 2520 REM 1 is the start to the cursor. Only 2 was implemented, and 0
 2530 REM is what full-screen programs actually use, so everything
 2540 REM below the cursor was being left behind.
 2550 DEF PROCerase
 2560 LOCAL x%,y%,i%,b%
 2570 IF p%(0)=2 THEN CLS:ENDPROC
 2580 x%=POS:y%=VPOS:b%=scb%-sct%
 2590 IF p%(0)=1 THEN PROCedtop(x%,y%):ENDPROC
 2600 PROCeol
 2610 FOR i%=y%+1 TO b%
 2620   VDU 31,0,i%
 2630   PROCblank(cols%-1)
 2640 NEXT
 2650 VDU 31,x%,y%
 2660 ENDPROC
 2670 :
 2680 DEF PROCedtop(x%,y%)
 2690 LOCAL i%
 2700 FOR i%=0 TO y%-1
 2710   VDU 31,0,i%
 2720   PROCblank(cols%-1)
 2730 NEXT
 2740 VDU 31,0,y%
 2750 PROCblank(x%+1)
 2760 VDU 31,x%,y%
 2770 ENDPROC
 2780 :
 2790 REM EL. 0 is cursor to end of line, 1 the start to the cursor,
 2800 REM 2 the whole line. No BBC primitive for any of them, so blank
 2810 REM and put the cursor back.
 2820 REM
 2830 REM NEVER touch the LAST column. Writing it auto-wraps, and on
 2840 REM the bottom row that scrolls the whole screen - once per line
 2850 REM repainted, which is why top marched off the bottom. The
 2860 REM original code stopped at 78 for exactly this reason; I
 2870 REM widened it to cols%-1 assuming VDU 23,16 scroll protection
 2880 REM was in force, and the Pi VDU driver does not honour it.
 2890 DEF PROCeol
 2900 LOCAL x%,y%
 2910 x%=POS:y%=VPOS
 2920 IF p%(0)=1 THEN VDU 31,0,y%:PROCblank(x%+1):VDU 31,x%,y%:ENDPROC
 2930 IF p%(0)=2 THEN VDU 31,0,y%:PROCblank(cols%-1):VDU 31,x%,y%:ENDPROC
 2940 PROCblank(cols%-1-x%)
 2950 VDU 31,x%,y%
 2960 ENDPROC
 2970 :
 2980 REM ================ keyboard ================
 2990 DEF PROCkeys
 3000 LOCAL k%
 3010 k%=INKEY(0)
 3020 IF k%<0 THEN ENDPROC
 3030 last%=TIME
 3040 IF k%=quitkey% THEN quit%=TRUE:ENDPROC
 3050 REM *FX4,1 makes the cursor keys report 136-139.
 3060 IF k%=139 THEN PROCarrow(65):ENDPROC
 3070 IF k%=138 THEN PROCarrow(66):ENDPROC
 3080 IF k%=137 THEN PROCarrow(67):ENDPROC
 3090 IF k%=136 THEN PROCarrow(68):ENDPROC
 3100 tx%?0=k%
 3110 PROCnet_send(1)
 3120 ENDPROC
 3130 :
 3140 DEF PROCarrow(f%)
 3150 tx%?0=27:tx%?1=91:tx%?2=f%
 3160 PROCnet_send(3)
 3170 ENDPROC
 3180 :
 3190 REM ================ transport - OSWORD &C0 ================
 3200 REM Everything below is replaced by BEEBNET calls when the
 3210 REM terminal moves to the co-processor.
 3220 DEF PROCnet_open
 3230 IF replay$<>"" THEN PROCnet_file:ENDPROC
 3240 PROCzero:blk%?2=&00
 3250 blk%!4=AFINET%:blk%!8=SOCKSTREAM%:blk%!12=0
 3260 PROCosw:PROCchk("create")
 3270 sock%=blk%!4
 3280 PROCzero:blk%?2=&12
 3290 blk%!4=sock%:blk%!8=FIONBIO%:!rx%=1:blk%!12=rx%
 3300 PROCosw
 3310 PROCsa
 3320 PROCzero:blk%?2=&04
 3330 blk%!4=sock%:blk%!8=sa%:blk%!12=16
 3340 PROCosw:PROCchk("connect")
 3350 ENDPROC
 3360 :
 3370 REM Adaptive read size - the technique proven at 3082 bytes/sec
 3380 REM in tput3.bas (5.5c), replacing one byte per call, which
 3390 REM capped this at 72. Socket_Recv normally satisfies the count
 3400 REM exactly or returns &1E, so it can be probed: double on
 3410 REM success, back to 1 on failure.
 3420 DEF FNnet_recv
 3430 LOCAL g%
 3440 IF fh%<>0 THEN =FNfile_recv
 3450 REM Set only the fields the call reads. PROCzero's 28-iteration
 3460 REM loop ran on every poll, and 98% of polls return &1E, so it
 3470 REM was most of the cost of finding out there was nothing there.
 3480 blk%?0=20:blk%?1=8:blk%?2=&05:blk%?3=0
 3490 blk%!4=sock%:blk%!8=rx%:blk%!12=rsz%:blk%!16=8
 3500 PROCosw
 3510 IF blk%?2<>0 THEN PROCdead
 3520 IF blk%?3<>0 THEN PROCless:=0
 3530 g%=blk%!4
 3540 REM Measured on hardware 2026-08-19, both cores: a serviced call
 3550 REM (+2 zeroed, +3 zero) can still return FEWER bytes than were
 3560 REM asked for - "asked 128 ... +4=83". Those bytes are real, and
 3570 REM rejecting them for not matching the count is what lost data
 3580 REM at exactly the point a short read happened. So +4 is a
 3590 REM range: 1..asked is data, 0 is a disconnect, negative is an
 3600 REM error, larger than asked is impossible.
 3610 IF g%<0 THEN PROCless:=0
 3620 IF g%=0 OR g%>rsz% THEN PROCless:=0
 3630 IF g%<rsz% THEN rsz%=1:=g%
 3640 IF rsz%<rmax% THEN rsz%=rsz%*2
 3650 =g%
 3660 :
 3670 REM &1E - the module could not satisfy that count, i.e. the pipe
 3680 REM just ran dry. Go straight back to 1 rather than halving.
 3690 REM tput3 halves and measured fine, but it measured a SATURATED
 3700 REM burst, where the size rarely overshoots. Interactive output
 3710 REM overshoots at the end of every command, and halving from 128
 3720 REM spends 128/64/32/16/8 as failed calls - five Tube round trips
 3730 REM delivering nothing - which is visible as a stutter. Dropping
 3740 REM to 1 costs one wasted call, and the ramp back is all reads.
 3750 DEF PROCless
 3760 rsz%=1
 3770 ENDPROC
 3780 :
 3790 DEF PROCnet_file
 3800 fh%=OPENIN(replay$)
 3810 IF fh%=0 THEN PRINT "cannot open ";replay$:END
 3820 ENDPROC
 3830 :
 3840 REM Replay source. Chunked the same way as the socket so the
 3850 REM parser sees the same shape of arrival, and EOF ends the run.
 3860 DEF FNfile_recv
 3870 LOCAL i%,n%
 3880 n%=0:i%=0
 3890 IF EOF#fh% THEN quit%=TRUE:=0
 3900 REPEAT
 3910   rx%?n%=BGET#fh%:n%=n%+1:i%=i%+1
 3920 UNTIL i%>=rsz% OR EOF#fh%
 3930 IF rsz%<rmax% THEN rsz%=rsz%*2
 3940 =n%
 3950 DEF PROCnet_send(n%)
 3960 IF fh%<>0 THEN ENDPROC
 3970 PROCzero:blk%?2=&08
 3980 blk%!4=sock%:blk%!8=tx%:blk%!12=n%:blk%!16=0
 3990 PROCosw
 4000 ENDPROC
 4010 :
 4020 DEF PROCnet_close
 4030 IF fh%<>0 THEN CLOSE#fh%:fh%=0:ENDPROC
 4040 PROCzero:blk%?2=&10:blk%!4=sock%
 4050 PROCosw
 4060 ENDPROC
 4070 :
 4080 REM sockaddr_in - layout is a GUESS, see specification.md 4.
 4090 DEF PROCsa
 4100 LOCAL i%,a%,b%,o%
 4110 FOR i%=0 TO 15:sa%?i%=0:NEXT
 4120 sa%?0=16:sa%?1=AFINET%
 4130 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 4140 a%=1:o%=4
 4150 FOR i%=1 TO 4
 4160   b%=INSTR(host$+".",".",a%)
 4170   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 4180   a%=b%+1:o%=o%+1
 4190 NEXT
 4200 ENDPROC
 4210 :
 4220 DEF PROCzero
 4230 LOCAL i%
 4240 FOR i%=0 TO 27:blk%?i%=0:NEXT
 4250 blk%?0=28:blk%?1=28:blk%?3=0
 4260 ENDPROC
 4270 :
 4280 DEF PROCosw
 4290 LOCAL A%,X%,Y%
 4300 A%=&C0:X%=blk% MOD 256:Y%=blk% DIV 256
 4310 CALL &FFF1
 4320 ENDPROC
 4330 :
 4340 REM +2 is zeroed by LANManager on every call - see §4.1.
 4350 DEF PROCchk(w$)
 4360 IF blk%?2<>0 THEN PROCtidy:PRINT "No socket module (";w$;")":END
 4370 IF blk%?3<>0 THEN PROCtidy:PRINT "Failed to ";w$;", r=";~blk%?3:END
 4380 ENDPROC
 4390 :
 4400 DEF PROCtidy
 4410 *FX4,0
 4420 *FX229,0
 4430 ENDPROC
 4440 :
 4450 DEF PROCfail
 4460 PROCtidy
 4470 PRINT:PRINT "Error ";ERR;" at line ";ERL
 4480 REPORT:PRINT
 4490 ENDPROC
 4500 :
 4510 REM 4.1: LANManager zeroes +2 on every call. If it survives, the
 4520 REM OSWORD went unclaimed and every other field is untouched -
 4530 REM +4 reads back as the socket number we put there, which looks
 4540 REM exactly like a byte count. Fail loudly rather than render
 4550 REM whatever happens to be in rx%.
 4560 DEF PROCdead
 4570 PROCtidy
 4580 VDU 26
 4590 PRINT
 4600 PRINT "*** socket module stopped answering (+2=";~blk%?2;")"
 4610 PRINT "OSWORD &C0 went unclaimed. See 2.4 and 7 Q1."
 4620 END
 4630 :
 4640 REM ============ screen geometry and regions ============
 4650 REM Walk the cursor out along each axis: a VDU 31 past the edge
 4660 REM is ignored, so the last position that sticks IS the edge.
 4670 REM Same technique as vdutest.bas, which measured 80x64 in mode
 4680 REM 21 - but mode 3 on the host is a different shape, so ask
 4690 REM rather than assume.
 4700 DEF PROCgeom
 4710 LOCAL x%,y%
 4720 cols%=0:rows%=0
 4730 CLS
 4740 FOR x%=0 TO 199
 4750   VDU 31,x%,0
 4760   IF POS=x% THEN cols%=x%+1
 4770 NEXT
 4780 FOR y%=0 TO 199
 4790   VDU 31,0,y%
 4800   IF VPOS=y% THEN rows%=y%+1
 4810 NEXT
 4820 IF cols%<2 THEN cols%=80
 4830 IF rows%<2 THEN rows%=25
 4840 VDU 30
 4850 ENDPROC
 4860 :
 4870 REM DECSTBM. A BBC text window IS a scrolling region - text
 4880 REM scrolls within it and leaves the rest of the screen alone -
 4890 REM so this maps onto the hardware rather than being emulated.
 4900 REM VDU 28 takes left,bottom,right,top; VDU 26 restores the
 4910 REM whole screen. Both home the cursor, as DECSTBM requires.
 4920 DEF PROCregion
 4930 LOCAL t%,b%
 4940 t%=p%(0):b%=p%(1)
 4950 IF t%<1 THEN t%=1
 4960 IF b%<1 OR b%>rows% THEN b%=rows%
 4970 IF t%>=b% THEN t%=1:b%=rows%
 4980 sct%=t%:scb%=b%
 4990 IF t%=1 AND b%=rows% THEN VDU 26 ELSE VDU 28,0,b%-1,cols%-1,t%-1
 5000 VDU 30
 5010 ENDPROC
 5020 :
 5030 REM ?1049 and the older ?47 - the alternate screen. The BBC has
 5040 REM no second screen buffer and no way to read the current one
 5050 REM back, so the previous contents CANNOT be restored on exit.
 5060 REM Clearing on both transitions is still much better than
 5070 REM ignoring it, which left top painting over the shell and
 5080 REM leaving its debris behind afterwards.
 5090 DEF PROCpriv(on%)
 5100 IF p%(0)<>1049 AND p%(0)<>47 THEN ENDPROC
 5110 IF on%=alt% THEN ENDPROC
 5120 alt%=on%
 5130 VDU 26
 5140 sct%=1:scb%=rows%
 5150 CLS
 5160 ENDPROC
 5170 :
 5180 REM Saved position is window-relative, and so is the restore, so
 5190 REM the pair stays consistent if a region is set between them.
 5200 DEF PROCsave
 5210 svx%=POS:svy%=VPOS
 5220 ENDPROC
 5230 :
 5240 DEF PROCrest
 5250 VDU 31,svx%,svy%
 5260 ENDPROC
 5270 :
 5280 REM Route VDU output to the Pi framebuffer. Which call works
 5290 REM depends on the core, and there is no way to ask - so it is
 5300 REM configuration, not detection. See vdu% at the top.
 5310 DEF PROCvdu
 5320 IF vdu%=1 THEN OSCLI("PIVDU "+STR$(pivdu%)):ENDPROC
 5330 IF vdu%=2 THEN CALL &300
 5340 ENDPROC
 5350 :
 5360 REM Read the whole screen back with OSBYTE 135 BEFORE printing
 5370 REM any of it - printing scrolls the thing being read. Every
 5380 REM row is bracketed with | so trailing spaces and short lines
 5390 REM are visible, and blank rows stand out.
 5400 DEF PROCdump
 5410 LOCAL x%,y%,c%
 5420 FOR y%=0 TO rows%-1
 5430   d$(y%)=""
 5440   FOR x%=0 TO cols%-1
 5450     VDU 31,x%,y%
 5460     A%=135:X%=0:Y%=0:c%=((USR&FFF4) AND &FF00) DIV 256
 5470     IF c%<32 OR c%>126 THEN c%=46
 5480     d$(y%)=d$(y%)+CHR$(c%)
 5490   NEXT
 5500 NEXT
 5510 VDU 26:CLS:VDU 2
 5520 FOR y%=0 TO rows%-1
 5530   PRINT y%;"|";d$(y%);"|"
 5540 NEXT
 5550 ENDPROC
 5560 :
 5570 DEF PROCblank(n%)
 5580 LOCAL i%
 5590 IF n%<1 THEN ENDPROC
 5600 FOR i%=1 TO n%:VDU 32:NEXT
 5610 ENDPROC
 5620 REM Startup geometry probe. The whole class of remaining faults
 5630 REM - line overflow, wrap, double spacing - turns on how wide
 5640 REM the screen really is and whether PROCgeom measured it, so
 5650 REM print both and let the screen answer instead of a photo.
 5660 REM The ruler is cols%-1 wide: it must end ONE column short of
 5670 REM the right edge and must not wrap onto a second line.
 5680 DEF PROCprobe
 5690 LOCAL i%
 5700 PRINT "measured ";cols%;" x ";rows%
 5710 FOR i%=1 TO cols%-1
 5720   IF i% MOD 10=0 THEN VDU 48+(i% DIV 10) MOD 10 ELSE VDU 46
 5730 NEXT
 5740 PRINT
 5750 PRINT "ruler above is ";cols%-1;" wide and must not have wrapped"
 5751 LOCAL v%
 5752 REM Send the full-width ruler through PROCvt, exactly as network
 5753 REM data goes, so this tests the DEFERRED WRAP emulation and not
 5754 REM raw VDU. Drawing it with PRINT measures the BBC's own
 5755 REM behaviour, which does wrap - that is the thing being worked
 5756 REM around, so it can never be the test of the workaround.
 5757 v%=VPOS
 5758 FOR i%=1 TO cols%
 5759   IF i% MOD 10=0 THEN PROCvt(48+(i% DIV 10) MOD 10) ELSE PROCvt(46)
 5760 NEXT
 5761 PROCvt(13):PROCvt(10)
 5762 PRINT "full ";cols%;"-wide ruler through PROCvt: ";
 5763 IF VPOS-v%>1 THEN PRINT "WRAPPED - deferred wrap not working" ELSE PRINT "fits - 80 columns usable"
 5764 ENDPROC
 5770 REM ================ colour ================
 5780 REM 2.3: mode 21 is 64 colours x 4 tints, and VDU 19 reprograms
 5790 REM the 16 low-bit palette entries. So rather than hunting for
 5800 REM which GCOL numbers happen to look like ANSI colours, DEFINE
 5810 REM logical 0-15 as the xterm ANSI 16 and address them directly.
 5820 REM Plain RESTORE, not RESTORE <line> - a line reference would
 5830 REM break renumbering, and these are the only DATA in the file.
 5840 DEF PROCpal
 5850 LOCAL l%,r%,g%,b%
 5860 RESTORE
 5870 FOR l%=0 TO 15
 5880   READ r%,g%,b%
 5890   VDU 19,l%,16,r%,g%,b%
 5900 NEXT
 5910 ENDPROC
 5920 :
 5930 DATA 0,0,0, 170,0,0, 0,170,0, 170,85,0
 5940 DATA 0,0,170, 170,0,170, 0,170,170, 170,170,170
 5950 DATA 85,85,85, 255,85,85, 85,255,85, 255,255,85
 5960 DATA 85,85,255, 255,85,255, 85,255,255, 255,255,255
 5970 :
 5980 DEF PROCsgr
 5990 LOCAL i%,v%
 6000 IF np%=0 AND p%(0)=0 THEN PROCsgrdef:PROCink:ENDPROC
 6010 FOR i%=0 TO np%
 6020   v%=p%(i%)
 6030   IF v%=0 THEN PROCsgrdef
 6040   IF v%=1 THEN bold%=TRUE
 6050   IF v%=22 THEN bold%=FALSE
 6060   IF v%=7 THEN rev%=TRUE
 6070   IF v%=27 THEN rev%=FALSE
 6080   IF v%>=30 AND v%<=37 THEN fg%=v%-30
 6090   IF v%>=90 AND v%<=97 THEN fg%=v%-82
 6100   IF v%=39 THEN fg%=7
 6110   IF v%>=40 AND v%<=47 THEN bg%=v%-40
 6120   IF v%>=100 AND v%<=107 THEN bg%=v%-92
 6130   IF v%=49 THEN bg%=0
 6140   IF v%=38 AND i%+2<=np% THEN IF p%(i%+1)=5 THEN fg%=FNx256(p%(i%+2)):i%=i%+2
 6150   IF v%=48 AND i%+2<=np% THEN IF p%(i%+1)=5 THEN bg%=FNx256(p%(i%+2)):i%=i%+2
 6160 NEXT
 6170 PROCink
 6180 ENDPROC
 6190 :
 6200 DEF PROCsgrdef
 6210 fg%=7:bg%=0:bold%=FALSE:rev%=FALSE
 6220 ENDPROC
 6230 :
 6240 REM VDU 17,n is text foreground, 17,128+n background. Bold is
 6250 REM the bright half of the 16, which is what a terminal does.
 6260 DEF PROCink
 6270 LOCAL f%,b%,t%
 6280 f%=fg%:b%=bg%
 6290 IF bold% AND f%<8 THEN f%=f%+8
 6300 IF rev% THEN t%=f%:f%=b%:b%=t%
 6310 VDU 17,f%
 6320 VDU 17,128+b%
 6330 ENDPROC
 6340 :
 6350 REM xterm-256 reduced to the 16 we define. 0-15 pass through,
 6360 REM 16-231 is a 6x6x6 cube thresholded to a colour plus a bright
 6370 REM bit, 232-255 is the grey ramp. Nearest-ish, not exact - 2.3
 6380 REM says an exact 256 is not on offer in this mode anyway.
 6390 DEF FNx256(n%)
 6400 LOCAL r%,g%,b%,v%,c%
 6410 IF n%<16 THEN =n%
 6420 IF n%>=232 THEN =FNgrey(n%-232)
 6430 v%=n%-16
 6440 b%=v% MOD 6:g%=(v% DIV 6) MOD 6:r%=v% DIV 36
 6450 c%=0
 6460 IF r%>2 THEN c%=c%+1
 6470 IF g%>2 THEN c%=c%+2
 6480 IF b%>2 THEN c%=c%+4
 6490 IF r%>3 OR g%>3 OR b%>3 THEN c%=c%+8
 6500 =c%
 6510 :
 6520 DEF FNgrey(v%)
 6530 IF v%<8 THEN =0
 6540 IF v%<16 THEN =8
 6550 IF v%<20 THEN =7
 6560 =15
