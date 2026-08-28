   10 REM > PTERM - the terminal client, on top of the FBVDU engine
   13 REM
   16 REM   CHAIN "PTERMRUN"     copro 15, *ARMBASIC, tube on, share mounted
   19 REM
   22 REM Phase 5. BEEBTERM's transport and keyboard, with its whole VT and
   25 REM rendering half deleted and replaced by two calls: PROCv_write for
   28 REM every byte in, FNv_flush once per drain. Everything BEEBTERM had to
   31 REM compensate for - no pending wrap, no second screen buffer, VDU 28
   34 REM standing in for a scrolling region, an alternate screen that cleared
   37 REM instead of restoring - is gone, because the engine has the real
   40 REM thing. 9.3 lists them; none of them appear below.
   43 REM
   46 REM What is inherited, because it was measured and works:
   49 REM
   52 REM   FNnet_recv's adaptive read sizing, which got 3082 bytes/sec where
   55 REM   one byte per call got 72 (5.5c)
   58 REM   the drain loop that polls the keyboard DURING a drain, so CTRL-]
   61 REM   still answers while a long listing is coming in
   64 REM   the IAC layer, refusing every option except echo and go-ahead
   67 REM
   70 REM What is new here:
   73 REM
   76 REM   SYS "OS_Word" instead of CALL &FFF1. There is no CALL &FFF1 on
   79 REM   ARM, and PTRTEST2 proved on hardware that the control block and
   82 REM   the buffers behind its pointers both cross the Tube on copro 15.
   85 REM   NAWS, so the far end is told the window is 80x64 and the
   88 REM   stty rows 64 cols 80 ritual in 3.5 is retired
   91 REM   cursor keys encoded per DECCKM, asked of the engine
   94 REM   the reply channel: DSR and DA answers go back up the socket
   97 :
  100 host$="192.0.2.10"
  101 REM ask%=TRUE prompts for the destination at startup. These are the
  102 REM defaults it offers, and what it uses if ask% is FALSE.
  103 port%=2323
  104 ask%=TRUE:dom$="lan"
  106 :
  109 cols%=80:rows%=64
  112 cw%=8:ch%=8
  115 md%=21:vdu%=1:pivdu%=2
  118 sim%=FALSE
  121 glass%=TRUE
  124 :
  127 REM drain%: bytes taken before the model is flushed and the loop turns.
  130 REM keyev%: bytes between keyboard polls DURING a drain. On a
  133 REM co-processor INKEY is an OSBYTE across the Tube, so one poll per
  136 REM byte would pay a round trip for every byte received.
  139 drain%=1024:keyev%=256
  142 REM 64, measured. FBSIZE ran a hundred peek-then-read cycles at each
  145 REM size against a saturated socket and counted the reads the module
  148 REM refused after its own peek had said the bytes were there:
  151 REM
  154 REM     1,2,4,8,16   100 of 100 ok, none refused
  157 REM     32, 64        46 of  46 ok, none refused
  160 REM     128           33 of  35 ok, TWO refused, the worst at 88
  163 REM
  166 REM So the ceiling is between 64 and 88, and a refusal is not a refusal
  169 REM - the module consumes the bytes and then reports failure, which is
  172 REM how 111 bytes went missing mid-stream and printed an escape
  175 REM sequence as text on the screen.
  178 rmax%=64
  181 quitkey%=29
  184 :
  187 AFINET%=2:SOCKSTREAM%=1
  190 mpeek%=1:mnowait%=8
  193 :
  196 REM replay$ feeds a captured stream through the whole client - the same
  199 REM pump, the same drain sizing, the same IAC layer, the same one flush
  202 REM per drain - with a file where the socket goes. It is how any of this
  205 REM gets tested offline: b-em has no network, and SOCKSTUB is 6502 code
  208 REM in host sideways RAM which cannot write ARM memory, so a socket read
  211 REM on copro 15 under the emulator reports bytes and delivers none.
  214 REM Both empty for the real thing.
  217 replay$=""
  220 dump$="RESGLAS"
  223 REM The banner costs a row, and a diagnostic run is compared against a
  226 REM replay of the server's log - which has no banner in it, so every
  229 REM line would be one row out and 505 cells would differ for no reason.
  232 banner%=TRUE
  235 err$="RESERR"
  238 REM rlog$ records every byte the transport delivered, in order, into
  241 REM memory - written out once at exit, because a BPUT per byte over
  244 REM LANManFS is 58ms each. Diffed against what socat logged sending it
  247 REM says whether bytes were LOST or DUPLICATED and exactly where, which
  250 REM is not a thing a photograph of a monitor can settle.
  253 rlog$="RXL"
  256 dbmax%=16384
  259 REM glass%check compares the PIXELS against the model at exit. The
  262 REM model has been proved right against pyte; what is left on the
  265 REM screen is cells the flush never repainted, and only the machine
  268 REM can say which ones.
  271 gcheck%=TRUE
  274 rlmax%=65536
  277 fh%=0:rlen%=0:rpos%=0
  280 :
  283 sock%=-1:quit%=FALSE:tstate%=0:tverb%=0:rsz%=1:naws%=FALSE
  286 got%=0:reads%=0:short%=0:e1e%=0
  289 d1%=0:d2%=0:d3%=0:lasta%=0:lastg%=0:closed%=FALSE
  292 busy%=0:idle%=0:naps%=0:lastgot%=0:pcx%=-1:pcy%=-1
  295 REM peek%=FALSE is the one call path; it turns itself on if that fails.
  298 peek%=FALSE:peeks%=0:fellback%=0:lasterr%=0
  301 REM sendtry% bounds the non-blocking send retry. sdrop% counts bytes the
  304 REM far end would not take, which used to vanish without trace.
  307 REM Thirty, not two hundred. A keystroke the far end will not take in
  310 REM thirty tries is worth dropping - at 3.28ms a call, two hundred is
  313 REM two thirds of a second of unbreakable stall per key, and the user
  316 REM reported the machine locking up while typing after a heavy burst.
  319 REM sretry%/smax% record whether it ever actually has to retry.
  322 sendtry%=30:sdrop%=0:sretry%=0:smax%=0
  325 REM A/B THE READ STRATEGY AGAINST A REAL SHELL.
  328 REM
  331 REM Every probe so far fed the Beeb from yes|head, which trickles. A real
  334 REM session does nothing at all and then dumps four kilobytes of ll output
  337 REM in one go, and the strategy that wins on a trickle need not be the one
  340 REM that wins on an avalanche - which is the moment that actually feels
  343 REM slow. So measure it here, on the real stream.
  346 REM
  349 REM way 1 is a bare read of rmax%. way 2 peeks for the count and pulls all
  352 REM of it in one call. They alternate every wslice% centiseconds so that
  355 REM bursts and idles fall on both roughly equally over a session, and both
  358 REM count OSWORD CALLS, so way 2 is charged for its peek.
  361 REM
  364 REM qmax% and the q* buckets record how much was ACTUALLY QUEUED whenever
  367 REM way 2 peeked. That is the number the whole argument turns on: if a real
  370 REM burst leaves thousands of bytes sitting there, one pull takes the lot
  373 REM and 64-at-a-time is leaving performance on the floor.
  376 REM THE BULK READ IS RETIRED. The queue really does hold thousands of
  379 REM bytes - 47 peeks in 68 found over 2048 waiting, qmax 4096 - but
  382 REM Socket_Recv will not hand them over. Asked for 1024 it refused, then
  385 REM 512, then 256, then 128, bottoming out at 64, and a refused read
  388 REM consumes what it refuses. So RESSIZE's refusals at 128 were real and
  391 REM dismissing them was wrong. The module meters data out 64 bytes at a
  394 REM time however much is queued, and no strategy at this end changes it.
  397 REM
  400 REM What stays is the measurement, because the depth is the evidence for
  403 REM where the remaining time goes. A peek is non-destructive and cannot
  406 REM lose a byte, so it is safe to keep - but it costs a call, so take one
  409 REM every qevery% reads rather than on every one.
  412 qask%=4096:qevery%=64
  415 REM MEASURE A BURST, NOT A SESSION.
  418 REM
  421 REM Every throughput figure in this project divides by time that is
  424 REM mostly idle, so none of them describe what is actually experienced.
  427 REM Real traffic is bimodal - nothing at all, then two to four kilobytes
  430 REM arriving at once - and the only rate that matters is how fast a burst
  433 REM drains once it is there.
  436 REM
  439 REM The gap this is chasing: a call costs 3.28ms and returns up to 64
  442 REM bytes, so the path we already have tops out near 17KB/sec. PTERM
  445 REM measures 2.4. Twelve percent. If a burst drains at anything close to
  448 REM 17KB/sec then the average is just idle time and there is nothing to
  451 REM fix; if it drains at 2.4KB/sec too, something is throttling us inside
  454 REM the burst and it is worth seven times more than a sideways ROM.
  457 REM
  460 REM A pump that moved burstmin% bytes or more counts as a burst. Its
  463 REM bytes, its centiseconds and its READS are kept apart from everything
  466 REM else, so the rate is burst-only and the per-read cost inside a burst
  469 REM can be compared against the 3280us a bare call is known to take.
  472 burstmin%=256:bursts%=0:bbytes%=0:bcs%=0:breads%=0
  475 qmax%=0:q1%=0:q2%=0:q3%=0:q4%=0:q5%=0
  478 gbad%=0:gfirst%=-1:gwhat$="":gpix$=""
  481 PROCsshcfg
  484 IF gcheck% THEN DIM gcol% 255, grow% 255, gops% 63
  487 IF gcheck% THEN FOR i%=0 TO 31:gops%?i%=0:NEXT
  490 REM MEASURED 2026-08-26: 3,937 socket reads carried 9,294 bytes and
  493 REM 3,767 of them - 95.7% - came back &1E empty. At 4.6ms a call that
  496 REM is 18s of a 26.6s session, while the 170 reads that DID carry data
  499 REM needed 0.8s between them. The module offers no select() and no
  502 REM timeout (see 4), so polling is forced and only the RATE is ours.
  505 REM
  508 REM napafter% empties before the first nap; it then grows 1cs per
  511 REM napgrow% further empties, capped at napmax%, resetting on a byte.
  514 REM napmax%=5 bounds keystroke latency to 50ms - keys are polled here
  517 REM too. napafter%=0 naps after EVERY empty read, BURSTS INCLUDED: at
  520 REM 2, act% reset idle% while data flowed, so output never backed off.
  523 napafter%=0:napgrow%=8:napmax%=5
  526 REM rx% must hold a PEEK, not just a read: a peek copies what is there
  529 REM into the buffer, so peeking 4096 can write 4096 bytes.
  532 DIM blk% 31, sa% 31, rx% 4095, tx% 63, dbuf% 96
  535 rlen2%=0
  538 REM crx% takes CIPHERTEXT off the module; rx% keeps its old job of
  541 IF rlog$<>"" THEN DIM rl% rlmax%
  544 IF ssh% THEN DIM crx% 1023, stx% 4095, sshkey% 79, sshnm% 63
  545 DIM nm2% 255, pk% 7, pw% 127
  547 IF dump$<>"" THEN DIM db% dbmax%
  550 dbp%=0
  553 ON ERROR PROCfail:END
  556 REM BEFORE PROCv_boot, because the test that reads it runs the
  559 REM instant boot returns. Setting it after was error 26 at the very
  562 REM line that reads it - BBC BASIC has no undefined value, only a
  565 REM missing variable.
  568 usemv%=TRUE
  571 REM Profiling. prof$ is APPENDED to every profcs% centiseconds, so a
  574 REM hard crash - one that never reaches ON ERROR - leaves a trail.
  577 REM
  580 REM IT WAS THE STUTTER, and file I/O was why: a snapshot used to be an
  583 REM OPENUP, a seek, three writes and a close - a whole SMB transaction
  586 REM on THE SAME module the socket uses. It now BUFFERS IN RAM and
  589 REM writes once, after the session ends, so the instrument no longer
  592 REM perturbs what it measures. profcs%=0 still disables it.
  595 prof$="RESPROF":profcs%=50:profn%=600:pn%=0
  596 REM Caps lock off BEFORE the prompt - PROCask says why. TWO LINES,
  597 REM because a * command takes the WHOLE REST OF ITS LINE: written
  598 REM as *FX202,48:*FX118 the OS gets one string and *FX118 never runs.
  599 *FX202,48
  600 *FX118
  601 tpump=0:tparse=0:tflush=0:tkeys=0:where%=0:pseq%=0:plast%=0:nflushes%=0
  602 IF profcs%>0 THEN DIM pf%(profn%,16),pb% profn%*112+256
  603 IF ask% THEN PROCask
  604 PROCv_boot
  607 REM ONE VARIABLE. Setting usemv% FALSE puts the scroll back on the
  610 REM interpreted loop while changing nothing else, so a lockup that
  613 REM survives it is not the assembled move. This is the same one-line
  616 REM elimination that found the cursor and the blank fast path, and it
  619 REM beat four rounds of theorising both times.
  622 IF NOT usemv% THEN fastmv%=FALSE
  625 profon%=TRUE
  628 PROCcalnap
  629 REM fastmv% is recorded in RESPROF's header, not printed. A line on
  630 REM the glass costs a row and shifts every row after it - which is
  631 REM why banner% exists: a run compared against a replay would be one
  632 REM line out and 505 cells would differ for no reason.
  634 IF vfail$<>"" THEN PROCstop(vfail$)
  637 REM OFF for this run: every stale cell on the glass has been a blank,
  640 REM and the blank fast path is the only route a blank takes that a
  643 REM character does not. If the stripes go, it is the culprit.
  646 fastblank%=TRUE
  649 REM The blank fast path was eliminated: 143 stale cells with it off.
  652 REM trace% did its job: stale_ops came back 1:27 on every stale cell,
  655 REM which turned out to be PTERM's own exit PRINT, and with that moved
  658 REM after the check the glass reports 0 stale cells. The artifact was
  661 REM scroll tearing, now fixed by clearing what the move exposes.
  664 REM OFF: the second cause was PROCv_clrg leaving the shadow stale.
  667 REM Note trace% is NOT a neutral instrument - it selects the
  670 trace%=FALSE
  673 REM The cursor is back on. PROCv_cur now marks the shadow as not
  676 REM matching the model at the cursor cell, so the flush repaints it
  679 REM whatever happens in between.
  682 cvis%=TRUE
  685 REM *FX4,1 makes the cursor keys report 136-139 instead of editing.
  688 REM *FX229,1 stops ESCAPE raising a BASIC Escape so the key returns 27
  691 REM and is sent. Without it ESC kills the client, which takes vi, less
  694 REM and every ncurses menu with it - and PROCtidy was restoring 229 to
  697 REM 0 having never set it.
  698 REM CAPS LOCK OFF for the session - the far end is Linux. The bits
  699 REM are INVERTED; PROCtidy explains, and puts it back on the way out.
  700 *FX4,1
  703 *FX229,1
  704 REM caps lock is already off - set at 600, before the prompt
  706 IF banner% THEN PROCbanner
  709 PROCnet_open
  712 PROCmain
  715 IF gcheck% THEN PROCglasscheck
  718 PROCdump
  721 REM AFTER the glass check: it PRINTs, and PRINT paints the glass raw.
  724 PROCprofdump
  727 PROCrlsave
  730 PROCnet_close
  733 PROCtidy
  736 VDU 23,1,1:VDU 26:CLS
  739 PRINT "PTERM closed."
  742 END
  745 :
  748 REM ================ the loop ================
  751 REM Bytes in, then ONE flush. That split is section 3's load-bearing
  754 REM decision and phase 4 measured what it buys: a top frame repaints
  757 REM 105 cells, not 5120, and the whole of a 23K capture drains and
  760 REM renders in 0.75 seconds.
  763 REM Through the engine, so it is on the screen the engine owns. A plain
  766 REM PRINT here would go through the Pi VDU driver onto cells the model
  769 REM believes are blank, and the shadow would then agree they need no
  772 REM painting - so the flush could never remove them.
  775 DEF PROCbanner
  778 LOCAL n%
  781 PROCv_writes("PTERM -> "+host$+":"+STR$(port%)+"   CTRL-] quits"+CHR$(13)+CHR$(10))
  784 n%=FNv_flush
  787 ENDPROC
  790 :
  793 REM The flush is SKIPPED when nothing arrived and the cursor has not
  796 REM moved. It walks all 5120 cells whether or not anything changed, and
  799 REM it takes the cursor down and puts it back every time - which with an
  802 REM idle socket is a scan and two cell repaints per pass, thousands of
  805 REM times a second. That is what made the cursor appear to flash.
  808 REM
  811 REM And after napafter% empty passes it waits a centisecond. An idle
  814 REM terminal was spending every one of them on a peek across the Tube:
  817 REM 4011 of 4115 reads in a measured session found nothing.
10000 DEF PROCmain
10010 LOCAL n%,act%,pt
10020 REPEAT
10030   where%=1:pt=TIME:PROCpump:tpump=tpump+(TIME-pt)
10040   act%=FALSE
10050   IF got%<>lastgot% OR cx%<>pcx% OR cy%<>pcy% THEN act%=TRUE
10060   where%=2:pt=TIME
10070   IF act% THEN n%=FNv_flush:lastgot%=got%:pcx%=cx%:pcy%=cy%:ncells%=ncells%+n%:nflushes%=nflushes%+1
10080   tflush=tflush+(TIME-pt)
10090 REM Only when there IS one. FNv_reply allocates a string on every
10100 REM call and we were calling it about eighty times a second to be
10110 REM told there was nothing to send. LEN on the engine buffer costs
10120 REM nothing and allocates nothing.
10130 where%=3:IF LEN(rep$)>0 THEN PROCreply
10140   where%=4:pt=TIME:PROCkeys:tkeys=tkeys+(TIME-pt)
10150   IF profcs%>0 THEN IF TIME-plast%>=profcs% THEN PROCprof
10160   REM act% has to be taken BEFORE lastgot% is updated, or the streak
10170   REM counts every pass as idle including the ones that just did work.
10180   IF act% THEN idle%=0 ELSE idle%=idle%+1
10190   IF idle%>napafter% THEN PROCbackoff
10200 UNTIL quit%
10210 ENDPROC
10220 :
10230 REM One centisecond. Long enough that an idle terminal stops hammering
10240 REM the Tube, short enough that the keyboard is still polled a hundred
10250 REM times a second and a byte arriving is acted on at once.
10260 REM THIS USED TO BE "t=TIME: REPEAT UNTIL TIME<>t" AND IT CRASHED THE
10270 REM MACHINE. On a co-processor TIME is read from the host, so spinning
10280 REM on it until the tick changes fires thousands of Tube transactions a
10290 REM tick, and after a few minutes of that the machine dies. FBSITN
10300 REM proved it: PTERM's nap and nothing else, no network, no files - dead
10310 REM inside five minutes, while the identical loop counting instead ran
10320 REM for ten with no trouble.
10330 REM
10340 REM It is a busy-wait written to avoid burning CPU which instead burned
10350 REM the Tube, and it is the cause of every "it locked up" in this
10360 REM session. The scroll, the assembler, the send path and the module
10370 REM were all investigated at length and all of them were innocent.
10380 REM
10390 REM A plain FOR loop waits just as well and makes no OS calls at all.
10400 DEF PROCnap
10410 LOCAL i%
10420 FOR i%=1 TO napn%:NEXT
10430 ENDPROC
10440 :
10450 REM Escalating backoff. Nothing here makes a call cheaper - that cost
10460 REM belongs to the module - so the only saving available is making
10470 REM fewer of them while idle, paid for in first-byte latency a human
10480 REM cannot see.
10490 DEF PROCbackoff
10500 LOCAL k%,j%
10510 k%=(idle%-napafter%) DIV napgrow%
10520 IF k%<1 THEN k%=1
10530 IF k%>napmax% THEN k%=napmax%
10540 FOR j%=1 TO k%:PROCnap:NEXT
10550 naps%=naps%+k%
10560 ENDPROC
10570 :
10580 REM How many empty FOR iterations make about a centisecond? Two TIME
10590 REM reads, not a spin - one measurement, at startup, then never again.
10600 REM BUG, found 2026-08-26 by profiling. This used to time a FIXED
10610 REM 20000 iterations, and on a 1.2GHz ARM that takes well under one
10620 REM centisecond - so d rounded to 0, was clamped to 1, and napn% came
10630 REM out 20000 for a loop that really costs a fraction of a cs. Every
10640 REM "one centisecond" nap was several times shorter than intended, so
10650 REM napmax%=5 bought about 15ms where it was meant to buy 50. The
10660 REM calibration was measuring a duration shorter than its own tick.
10670 REM It now GROWS the count until the measurement is long enough for
10680 REM the tick to be noise - 20cs, so quantisation is 5% - then divides.
10690 DEF PROCcalnap
10700 LOCAL t,i%,d,n%
10710 n%=20000
10720 REPEAT
10730   t=TIME
10740   FOR i%=1 TO n%:NEXT
10750   d=TIME-t
10760   IF d<20 THEN n%=n%*4
10770 UNTIL d>=20 OR n%>40000000
10780 napn%=n%/d
10790 IF napn%<20 THEN napn%=20
10800 IF napn%>100000 THEN napn%=100000
10810 ENDPROC
10820 :
10830 REM busy% accumulates only the time in which bytes were actually moving,
10840 REM so got%/busy% is "when there is something to read, how fast is it
10850 REM read" - the number 5.5c's 3082 bytes/sec was meant to be, before it
10860 REM turned out to have been measured with a read that dropped data.
10870 REM One line per snapshot, APPENDED and closed each time. Keeping the
10880 REM file open would be faster but a crash would lose the buffer, and the
10890 REM whole point is to survive a crash. where% says which region was
10900 REM running: 1 pump, 2 flush, 3 reply, 4 keys, 11 socket read, 12 parse.
10910 DEF PROCprof
10920 plast%=TIME:pseq%=pseq%+1
10930 IF pn%>=profn% THEN ENDPROC
10940 pf%(pn%,0)=TIME:pf%(pn%,1)=where%:pf%(pn%,2)=got%
10950 pf%(pn%,3)=INT(tpump):pf%(pn%,4)=INT(tparse):pf%(pn%,5)=INT(tflush):pf%(pn%,6)=INT(tkeys)
10960 pf%(pn%,7)=nscroll%:pf%(pn%,8)=INT(tscroll):pf%(pn%,9)=nflushes%:pf%(pn%,10)=ncells%
10970 pf%(pn%,11)=reads%:pf%(pn%,12)=e1e%:pf%(pn%,13)=bursts%
10980 pf%(pn%,14)=bbytes%:pf%(pn%,15)=INT(bcs%):pf%(pn%,16)=breads%
10990 pn%=pn%+1
11000 ENDPROC
11010 :
11020 REM Written ONCE, after PROCmain returns, AND IN ONE OSFILE.
11030 REM PROCef does a BPUT PER CHARACTER, and over LANManFS a 32KB
11040 REM dump is minutes of writing - which is what made CTRL-] look
11050 REM like a hang. PROCrlsave already carried the answer, and its
11060 REM comment says it: one OSFILE, not a BPUT per byte.
11070 DEF PROCprofdump
11080 LOCAL i%,j%,s$
11090 IF profcs%<1 THEN ENDPROC
11100 IF pn%<1 THEN ENDPROC
11110 pp%=0
11120 PROCpb("# cols t where got pump parse flush keys nscroll tscroll nflush ncells reads e1e bursts bbytes bcs breads")
11130 PROCpb("# snapshots="+STR$(pn%)+" every="+STR$(profcs%)+"cs drain="+STR$(drain%)+" rmax="+STR$(rmax%)+" fastmv="+STR$(fastmv%))
11140 FOR i%=0 TO pn%-1
11150   s$=STR$(pf%(i%,0))
11160   FOR j%=1 TO 16:s$=s$+" "+STR$(pf%(i%,j%)):NEXT
11170   PROCpb(s$)
11180 NEXT
11190 OSCLI("SAVE "+prof$+" "+STR$~pb%+" +"+STR$~pp%)
11200 PRINT "prof: ";pn%;" snapshots -> ";prof$
11210 ENDPROC
11220 :
11230 REM One line into the buffer: no file handle, no BPUT, and no
11240 REM LANManFS round trip per character. The counters are still
11250 REM dumped raw and cumulative, so the analysis differences them and
11260 REM a dropped snapshot costs one row instead of corrupting the rest.
11270 DEF PROCpb(s$)
11280 LOCAL i%
11290 FOR i%=1 TO LEN(s$):pb%?pp%=ASC(MID$(s$,i%,1)):pp%=pp%+1:NEXT
11300 pb%?pp%=13:pp%=pp%+1:pb%?pp%=10:pp%=pp%+1
11310 ENDPROC
11320 :
11330 DEF PROCpump
11340 LOCAL n%,t%,kp%,t0,r0%,el,pt2
11350 t%=0:kp%=0
11360 t0=TIME
11370 r0%=reads%
11380 REPEAT
11390   where%=11
11400   n%=FNnet_recv
11410   where%=12
11420   IF n%>0 THEN pt2=TIME:PROCemit(n%):tparse=tparse+(TIME-pt2)
11430   t%=t%+n%
11440   IF t%-kp%>=keyev% THEN PROCkeys:kp%=t%
11450 UNTIL n%<1 OR t%>drain% OR quit%
11460 el=TIME-t0
11470 IF t%>0 THEN busy%=busy%+el
11480 IF t%>=burstmin% THEN PROCburst(t%,el,reads%-r0%)
11490 ENDPROC
11500 :
11510 REM One drain that actually had something to drain.
11520 DEF PROCburst(b%,el,r%)
11530 bursts%=bursts%+1:bbytes%=bbytes%+b%:bcs%=bcs%+el:breads%=breads%+r%
11540 ENDPROC
11550 :
11560 REM Guarded: a BBC FOR always runs once, so 0 TO -1 would feed the
11570 REM parser a byte that was never received.
11580 DEF PROCemit(n%)
11590 LOCAL i%
11600 IF n%<1 THEN ENDPROC
11610 got%=got%+n%
11620 IF rlog$<>"" THEN PROCrl(n%)
11630 FOR i%=0 TO n%-1:PROCbyte(rx%?i%):NEXT
11640 ENDPROC
11650 :
11660 DEF PROCrl(n%)
11670 LOCAL i%
11680 FOR i%=0 TO n%-1
11690   IF rlen2%<rlmax% THEN rl%?rlen2%=rx%?i%:rlen2%=rlen2%+1
11700 NEXT
11710 ENDPROC
11720 :
11730 REM One OSFILE, not a BPUT per byte.
11740 DEF PROCrlsave
11750 IF rlog$="" OR rlen2%<1 THEN ENDPROC
11760 OSCLI("SAVE "+rlog$+" "+STR$~rl%+" +"+STR$~rlen2%)
11770 ENDPROC
11780 :
11790 DEF PROCbyte(c%)
11800 IF ssh% THEN PROCv_write(c%):ENDPROC
11810 IF tstate%>0 THEN PROCtelnet(c%):ENDPROC
11820 IF c%=255 THEN tstate%=1:ENDPROC
11830 PROCv_write(c%)
11840 ENDPROC
11850 :
11860 REM ================ telnet IAC ================
11870 DEF PROCtelnet(c%)
11880 IF tstate%=1 THEN PROCiac(c%):ENDPROC
11890 IF tstate%=2 THEN PROCiacopt(c%):ENDPROC
11900 IF tstate%=3 AND c%=255 THEN tstate%=4:ENDPROC
11910 IF tstate%=3 THEN ENDPROC
11920 IF tstate%=4 AND c%=240 THEN tstate%=0:ENDPROC
11930 IF tstate%=4 THEN tstate%=3
11940 ENDPROC
11950 :
11960 DEF PROCiac(c%)
11970 IF c%=255 THEN tstate%=0:PROCv_write(255):ENDPROC
11980 IF c%=250 THEN tstate%=3:ENDPROC
11990 IF c%>=251 AND c%<=254 THEN tverb%=c%:tstate%=2:ENDPROC
12000 tstate%=0
12010 ENDPROC
12020 :
12030 REM 251=WILL 252=WONT 253=DO 254=DONT ; 1=ECHO 3=SGA 31=NAWS
12040 REM
12050 REM NAWS is the one option we ASK for. Without it the far end assumes
12060 REM 24x80 and every full-screen program draws to the wrong size, which
12070 REM is what 3.5's stty rows 64 cols 80 was working around.
12080 DEF PROCiacopt(o%)
12090 LOCAL r%
12100 tstate%=0
12110 IF tverb%=253 AND o%=31 THEN PROCnawson:ENDPROC
12120 r%=0
12130 IF tverb%=251 THEN r%=254:IF o%=1 OR o%=3 THEN r%=253
12140 IF tverb%=253 THEN r%=252
12150 IF r%=0 THEN ENDPROC
12160 tx%?0=255:tx%?1=r%:tx%?2=o%
12170 PROCnet_send(3)
12180 ENDPROC
12190 :
12200 DEF PROCnawson
12210 naws%=TRUE
12220 tx%?0=255:tx%?1=251:tx%?2=31
12230 PROCnet_send(3)
12240 PROCnaws
12250 ENDPROC
12260 :
12270 REM IAC SB NAWS <width hi> <width lo> <height hi> <height lo> IAC SE.
12280 REM A 255 in any of the four would have to be doubled; 80 and 64 are
12290 REM not, and neither is any geometry this engine can be built at.
12300 DEF PROCnaws
12310 IF ssh% THEN PROCssh_size:ENDPROC
12320 IF NOT naws% THEN ENDPROC
12330 tx%?0=255:tx%?1=250:tx%?2=31
12340 tx%?3=cols% DIV 256:tx%?4=cols% MOD 256
12350 tx%?5=rows% DIV 256:tx%?6=rows% MOD 256
12360 tx%?7=255:tx%?8=240
12370 PROCnet_send(9)
12380 ENDPROC
12390 :
12400 REM ================ the reply channel ================
12410 REM DSR and DA answers. Nothing on the BBC side could answer a cursor
12420 REM position report before the engine existed - 9.3 had no way to know
12430 REM where the cursor was, because the driver owned it.
12440 DEF PROCreply
12450 LOCAL r$,i%,n%
12460 r$=FNv_reply
12470 n%=LEN(r$)
12480 IF n%<1 THEN ENDPROC
12490 IF n%>63 THEN n%=63
12500 FOR i%=1 TO n%:tx%?(i%-1)=ASC(MID$(r$,i%,1)):NEXT
12510 PROCnet_send(n%)
12520 ENDPROC
12530 :
12540 REM ================ keyboard ================
12550 REM *FX4,1 makes the cursor keys report 136-139 instead of editing.
12560 DEF PROCkeys
12570 LOCAL k%
12580 k%=INKEY(0)
12590 IF k%<0 THEN ENDPROC
12600 IF k%=quitkey% THEN quit%=TRUE:ENDPROC
12610 IF k%=139 THEN PROCarrow(65):ENDPROC
12620 IF k%=138 THEN PROCarrow(66):ENDPROC
12630 IF k%=137 THEN PROCarrow(67):ENDPROC
12640 IF k%=136 THEN PROCarrow(68):ENDPROC
12650 tx%?0=k%
12660 PROCnet_send(1)
12670 ENDPROC
12680 :
12690 REM DECCKM, asked of the engine rather than assumed. In application
12700 REM cursor key mode the far end expects ESC O A, not ESC [ A, and a
12710 REM full-screen editor that set the mode gets the wrong key without
12720 REM this. BEEBTERM always sent ESC [ because it had nowhere to keep
12730 REM the mode.
12740 DEF PROCarrow(f%)
12750 tx%?0=27
12760 IF FNv_mode(1) THEN tx%?1=79 ELSE tx%?1=91
12770 tx%?2=f%
12780 PROCnet_send(3)
12790 ENDPROC
12800 :
12810 REM ================ transport - OSWORD &C0 ================
12820 DEF PROCnet_open
12830 IF replay$<>"" THEN PROCnet_file:ENDPROC
12840 PROCzero:blk%?2=&00
12850 blk%!4=AFINET%:blk%!8=SOCKSTREAM%:blk%!12=0
12860 PROCosw:PROCchk("create")
12870 sock%=blk%!4
12880 PROCsa
12890 PROCconnect
12920 IF ssh% THEN PROCssh_open
12930 ENDPROC
12940 :
12950 DEF PROCclosed
12955 LOCAL n%
12960 IF closed% THEN ENDPROC
12970 closed%=TRUE
12980 quit%=TRUE
12990 PROCv_writes(CHR$(13)+CHR$(10)+"[connection closed]"+CHR$(13)+CHR$(10))
12995 n%=FNv_flush
12996 REM FLUSH IT, or the message is written to the model and never
12997 REM painted: quit% ends PROCmain before the next flush, so the
12998 REM user never saw "[connection closed]" and the glass check
12999 REM reported its 18 cells as stale - which is exactly what it is for.
13000 ENDPROC
13010 :
13020 DEF PROCrefused(a%)
13030 d2%=d2%+1:e1e%=e1e%+1:lasta%=a%
13040 IF rmax%>1 THEN rmax%=rmax% DIV 2
13050 ENDPROC
13060 :
13070 REM The adaptive read, unchanged from 5.5c: double on a full read, drop
13080 REM straight back to 1 on &1E. A serviced call can return FEWER bytes
13090 REM than were asked for and those bytes are real, so +4 is a range.
13100 REM reads%, short% and got% are the accounting that says whether the
13110 REM transport is honest. If the model on the Beeb disagrees with a
13120 REM replay of what the server logged sending, the bytes went missing
13130 REM between the socket and PROCv_write, and the count is the evidence.
13140 REM PEEK FIRST, THEN READ EXACTLY WHAT IS THERE.
13150 REM
13160 REM Asking Socket_Recv for more than the module holds loses the
13170 REM difference - measured on hardware, 250 bytes gone from one session,
13180 REM and the screen fault it makes is an escape sequence that loses its
13190 REM ESC[ and prints its parameters as text. The old answer was to ask
13200 REM for one byte at a time, which cannot over-ask but costs a Tube round
13210 REM trip per byte.
13220 REM
13230 REM FBPEEK settled the better answer on hardware. MSG_PEEK is
13240 REM non-destructive - peek the same bytes twice and they are still there
13250 REM - and an OVER-ASKED peek REPORTS what it found rather than refusing:
13260 REM asked for 200 with 116 available it answered 116. So one peek sizes
13270 REM the read exactly. Two round trips per read instead of one, for up to
13280 REM 128 bytes instead of one, and never a byte lost.
13290 DEF FNnet_recv
13300 LOCAL g%,a%
13310 IF ssh% THEN =FNssh_recv
13320 IF fh%<>0 THEN =FNfile_recv
13330 reads%=reads%+1
13340 IF peek% THEN =FNnet_peekrecv
13350 IF qevery%>0 AND (reads% MOD qevery%)=0 THEN PROCqpeek
13360 REM WAY 1: one call, take what comes. Cheapest per call, and it won every
13370 REM synthetic comparison - but every one of those was fed by yes|head,
13380 REM which trickles. Whether it still wins when a real shell dumps four
13390 REM kilobytes at once is exactly what the A/B above is for, and the
13400 REM queue-depth buckets are what will say why.
13410 blk%?0=20:blk%?1=8:blk%?2=&05:blk%?3=0
13420 blk%!4=sock%:blk%!8=rx%:blk%!12=rmax%:blk%!16=mnowait%
13430 PROCosw
13440 IF blk%?2<>0 THEN PROCdead
13450 IF blk%?3=&1E THEN e1e%=e1e%+1:=0
13460 IF blk%?3<>0 THEN PROCnopeek(blk%?3):=0
13470 g%=blk%!4
13480 IF g%=0 THEN PROCclosed:=0
13490 IF g%<0 THEN =0
13500 IF g%>rmax% THEN d1%=d1%+1:lasta%=g%:=0
13510 =g%
13520 :
13530 REM Look, but do not touch. MSG_PEEK cannot consume, so this samples how
13540 REM deep the queue is without risking the stream.
13550 DEF PROCqpeek
13560 PROCzero:blk%?2=&05
13570 blk%!4=sock%:blk%!8=rx%:blk%!12=qask%:blk%!16=mpeek%+mnowait%
13580 PROCosw
13590 IF blk%?2<>0 THEN ENDPROC
13600 IF blk%?3<>0 THEN ENDPROC
13610 IF blk%!4>0 THEN PROCqlog(blk%!4)
13620 ENDPROC
13630 :
13640 REM How deep was the queue when we looked? This is the evidence, not the
13650 REM throughput: a burst that leaves thousands of bytes waiting means one
13660 REM pull would take the lot.
13670 DEF PROCqlog(a%)
13680 IF a%>qmax% THEN qmax%=a%
13690 IF a%<=64 THEN q1%=q1%+1:ENDPROC
13700 IF a%<=256 THEN q2%=q2%+1:ENDPROC
13710 IF a%<=1024 THEN q3%=q3%+1:ENDPROC
13720 IF a%<=2048 THEN q4%=q4%+1:ENDPROC
13730 q5%=q5%+1
13740 ENDPROC
13750 :
13760 DEF PROCnopeek(e%)
13770 peek%=TRUE:lasterr%=e%:fellback%=fellback%+1
13780 ENDPROC
13790 :
13800 DEF FNnet_peekrecv
13810 LOCAL g%,a%
13820 blk%?0=20:blk%?1=8:blk%?2=&05:blk%?3=0
13830 peeks%=peeks%+1
13840 blk%!4=sock%:blk%!8=rx%:blk%!12=rmax%:blk%!16=mpeek%+mnowait%
13850 PROCosw
13860 IF blk%?2<>0 THEN PROCdead
13870 IF blk%?3<>0 THEN e1e%=e1e%+1:=0
13880 REM +3 zero with a count of zero is EOF - the far end has closed. +3 of
13890 REM &1E is "nothing yet". Treating both as "no data" is why the client
13900 REM span silently forever when the shell exited, which from the outside
13910 REM looks exactly like the terminal stopping for no reason.
13920 a%=blk%!4
13930 IF a%=0 THEN PROCclosed:=0
13940 IF a%<0 THEN =0
13950 IF a%>rmax% THEN d1%=d1%+1:lasta%=a%:=0
13960 REM Exactly a% bytes, which the peek has just proved are there.
13970 blk%?0=20:blk%?1=8:blk%?2=&05:blk%?3=0
13980 blk%!4=sock%:blk%!8=rx%:blk%!12=a%:blk%!16=mnowait%
13990 PROCosw
14000 IF blk%?2<>0 THEN PROCdead
14010 REM These three discard a read the module has already handed over. 111
14020 REM bytes went missing in one event on hardware and the only ways that
14030 REM can happen are here, so each is counted separately rather than
14040 REM guessed between.
14050 REM A refusal here has already cost us a% bytes - they are gone. So the
14060 REM ceiling comes down, and keeps coming down, rather than losing the
14070 REM same way again. 64 is measured safe but a different machine, a
14080 REM different module or a busier socket need not agree, and silent
14090 REM corruption is far worse than being slow.
14100 IF blk%?3<>0 THEN PROCrefused(a%):=0
14110 g%=blk%!4
14120 IF g%<1 OR g%>a% THEN d3%=d3%+1:lasta%=a%:lastg%=g%:=0
14130 IF g%<a% THEN short%=short%+1
14140 =g%
14150 :
14160 REM Non-blocking, and it checks how much actually went.
14170 REM
14180 REM This used to send with flags=0 - BLOCKING - and ignore the count. Two
14190 REM faults in four lines. FBCOST hung the machine outright on a 256 byte
14200 REM send to a far end that was not reading: the call never returned and
14210 REM the Beeb had to be broken out of. PTERM survived only because it
14220 REM never sends more than nine bytes at a time.
14230 REM
14240 REM A send can also report FEWER bytes taken than it was given, and
14250 REM ignoring that silently drops the rest - the same class of bug as the
14260 REM over-asked read that was quietly losing 250 bytes a session.
14270 REM
14280 REM So: MSG_DONTWAIT, loop on what is left, and give up after tries%
14290 REM rather than spin for ever if the far end has stopped reading. A
14300 REM keystroke that does not arrive is bad; a terminal that locks up
14310 REM needing the BREAK key is worse.
14320 DEF PROCnet_send(n%)
14330 IF ssh% THEN PROCssh_send(n%):ENDPROC
14340 LOCAL s%,g%,t%
14350 IF n%<1 OR fh%<>0 THEN ENDPROC
14360 s%=0:t%=0
14370 REPEAT
14380   PROCzero:blk%?2=&08
14390   blk%!4=sock%:blk%!8=tx%+s%:blk%!12=n%-s%:blk%!16=mnowait%
14400   PROCosw
14410   IF blk%?2<>0 THEN PROCdead
14420   g%=0
14430   IF blk%?3=0 THEN g%=blk%!4
14440   IF g%>0 THEN s%=s%+g%
14450   IF g%<1 THEN t%=t%+1
14460 REM quit% MUST be in the condition. PROCdead sets it when the module
14470 REM stops claiming the OSWORD, and without it here the loop carried on
14480 REM retrying a socket that is already gone - sendtry% calls at 3.28ms
14490 REM each, with nothing able to interrupt.
14500 UNTIL s%>=n% OR t%>sendtry% OR quit%
14510 IF t%>0 THEN sretry%=sretry%+t%
14520 IF t%>smax% THEN smax%=t%
14530 IF s%<n% THEN sdrop%=sdrop%+(n%-s%)
14540 ENDPROC
14550 :
14560 DEF PROCnet_close
14570 IF fh%<>0 THEN fh%=0:ENDPROC
14580 IF sock%<0 THEN ENDPROC
14590 PROCzero:blk%?2=&10:blk%!4=sock%
14600 PROCosw
14610 sock%=-1
14620 ENDPROC
14630 :
14640 REM Loaded in one operation and then walked in memory. Read with BGET#
14650 REM a byte at a time it is 58ms per byte under the emulator - a Tube
14660 REM round trip and a host filing system call each - which is twenty
14670 REM minutes for a 23K capture.
14680 DEF PROCnet_file
14690 LOCAL f%
14700 f%=OPENIN(replay$)
14710 IF f%=0 THEN PROCstop("cannot open "+replay$)
14720 rlen%=EXT#f%
14730 CLOSE#f%
14740 IF rlen%<1 THEN PROCstop(replay$+" is empty")
14750 DIM rbuf% rlen%
14760 OSCLI("LOAD "+replay$+" "+STR$~rbuf%)
14770 rpos%=0:fh%=1
14780 ENDPROC
14790 :
14800 REM The same shape as the socket read, ramp included, so what is under
14810 REM test is the drain behaviour and not a different one.
14820 DEF FNfile_recv
14830 LOCAL i%,g%
14840 IF rpos%>=rlen% THEN quit%=TRUE:=0
14850 g%=rsz%
14860 IF rpos%+g%>rlen% THEN g%=rlen%-rpos%
14870 FOR i%=0 TO g%-1:rx%?i%=rbuf%?(rpos%+i%):NEXT
14880 rpos%=rpos%+g%
14890 IF rsz%<rmax% THEN rsz%=rsz%*2
14900 =g%
14910 :
14920 REM Keep the glass, force every cell to be repainted, and see which
14930 REM pixels change. A cell that changes is one the flush believed was
14940 REM already correct and was not - which is exactly what a stuck
14950 REM character on the screen is. The model is not in question: it has
14960 REM matched pyte cell for cell on this very stream.
14970 DEF PROCglasscheck
14980 LOCAL x%,y%,l%,i%,r%,q%,n%,bad%,shown$
14990 IF NOT glass% THEN ENDPROC
15000 REM Take the cursor DOWN before snapshotting, not merely forget it. A
15010 REM drawn cursor is a cell the glass and the model are entitled to
15020 REM disagree about, so leaving it in the snapshot makes the check
15030 REM report it every time: the one stale cell in the 01:45 run was a
15040 REM solid block at 17,1, which is exactly where the cursor rests after
15050 REM a sixteen character prompt and a space. Clearing con% without
15060 REM erasing was measuring the instrument, not the engine.
15070 IF con% THEN PROCv_uncur
15080 REM gb% holds one cell of decoded glass rows so FNglyph can build the
15090 REM pattern once and compare it against 95 font entries, rather than
15100 REM re-reading pixels for each candidate.
15110 gtxt$=""
15120 DIM gc% rows%*ch%*pit%, gb% 15
15130 FOR i%=0 TO rows%*ch%*pit%-4 STEP 4:gc%!i%=fb%!i%:NEXT
15140 FOR i%=0 TO cols%*rows%-1:shd%!(i%*4)=NOT scr%!(i%*4):NEXT
15150 cvis%=FALSE
15160 n%=FNv_flushg
15170 REM Counted per COLUMN and per ROW rather than listed. Eighty-eight
15180 REM coordinates do not fit in a line and the shape is what matters:
15190 REM three columns repeated down the screen says something structural,
15200 REM a scatter says something else entirely.
15210 bad%=0
15220 FOR x%=0 TO cols%-1:gcol%?x%=0:NEXT
15230 FOR y%=0 TO rows%-1:grow%?y%=0:NEXT
15240 FOR y%=0 TO rows%-1
15250   FOR x%=0 TO cols%-1
15260     IF FNcelldiff(x%,y%) THEN PROCmark(x%,y%):bad%=bad%+1
15270   NEXT
15280 NEXT
15290 gbad%=bad%
15300 ENDPROC
15310 :
15320 REM What the MODEL holds at a stale cell. If they are all blanks the
15330 REM erase path is not clearing the glass; if they all carry the same
15340 REM colour or the reverse flag, that names the path too. The glass has
15350 REM already been proved wrong and the model right, so this is the one
15360 REM piece of evidence still missing.
15370 DEF PROCmark(x%,y%)
15380 LOCAL a%
15390 LOCAL c%
15400 IF gcol%?x%<255 THEN gcol%?x%=gcol%?x%+1
15410 IF grow%?y%<255 THEN grow%?y%=grow%?y%+1
15420 IF gfirst%<0 THEN gfirst%=y%*cols%+x%
15430 REM Which operation last wrote this cell's shadow entry. 1 painted by
15440 REM the flush, 4 init, 8 scrolled up, 16 scrolled down, and the scroll
15450 REM carries the source's code - so 9 is painted then scrolled. A stale
15460 REM cell reading 1 means the flush painted it and the pixels are still
15470 REM wrong, which would be the blitter; anything with 8 or 16 means a
15480 REM scroll moved a shadow entry that did not match the glass.
15490 c%=ops%?(y%*cols%+x%)
15500 IF c%<32 THEN gops%?c%=gops%?c%+1
15510 REM WHAT IS ACTUALLY DRAWN, as text. Six cells of hex could not
15520 REM identify the source of a 27-cell run, and 27 cells of hex will not
15530 REM fit in a BASIC string. The font is in memory, so decode the glass
15540 REM back to characters and report the lot on one line. It can then be
15550 REM matched against the model's own grid rows: if the glass is holding
15560 REM some OTHER row, that is a scroll off-by-N and not the blitter.
15570 IF LEN(gtxt$)<200 THEN gtxt$=gtxt$+FNglyph(x%,y%)
15580 IF LEN(gwhat$)>120 THEN ENDPROC
15590 a%=scr%+(y%*cols%+x%)*4
15600 gwhat$=gwhat$+STR$(x%)+","+STR$(y%)+"="+STR$(a%?0)+"op"+STR$(c%)+" "
15610 REM What the GLASS shows there, read out of the copy taken before the
15620 REM repaint and decoded back into eight rows of bits against the cell's
15630 REM own background. FF FF FF FF FF FF FF FF is a solid block, which is
15640 REM a cursor left behind; anything else is a character that was never
15650 REM painted over. Those are opposite causes and no amount of inference
15660 REM has separated them.
15670 IF LEN(gpix$)>120 THEN ENDPROC
15680 gpix$=gpix$+STR$(x%)+","+STR$(y%)+":"+FNbits(x%,y%,a%?3)+" "
15690 ENDPROC
15700 :
15710 DEF FNbits(x%,y%,bg%)
15720 LOCAL l%,i%,b%,q%,s$
15730 s$=""
15740 FOR l%=0 TO ch%-1
15750   q%=gc%+(y%*ch%+l%)*pit%+x%*cw%
15760   b%=0
15770   FOR i%=0 TO cw%-1
15780     IF q%?i%<>bg% THEN b%=b%+2^(cw%-1-i%)
15790   NEXT
15800   s$=s$+RIGHT$("0"+STR$~b%,2)
15810 NEXT
15820 =s$
15830 :
15840 REM Which columns, and how many in each.
15850 DEF FNhist(p%,n%)
15860 LOCAL i%,s$
15870 s$=""
15880 FOR i%=0 TO n%-1
15890   IF p%?i%>0 AND LEN(s$)<180 THEN s$=s$+STR$(i%)+":"+STR$(p%?i%)+" "
15900 NEXT
15910 =s$
15920 :
15930 REM One cell of pixels, glass against the copy taken before the repaint.
15940 DEF FNcelldiff(x%,y%)
15950 LOCAL l%,r%,q%
15960 FOR l%=0 TO ch%-1
15970   r%=fb%+(y%*ch%+l%)*pit%+x%*cw%
15980   q%=gc%+(y%*ch%+l%)*pit%+x%*cw%
15990   IF !r%<>!q% OR r%!4<>q%!4 THEN =TRUE
16000 NEXT
16010 =FALSE
16020 :
16030 REM The screen as text, in the format tools/vtdiff.py reads, so a replay
16040 REM through the CLIENT can be diffed against pyte exactly as phase 3
16050 REM diffed a replay through the engine alone.
16060 DEF PROCdump
16070 LOCAL x%,y%,h%
16080 IF dump$="" THEN ENDPROC
16090 h%=0:dbp%=0
16100 PROCwl(h%,"[pterm1]")
16110 PROCwl(h%,"geometry="+STR$(cols%)+"x"+STR$(rows%))
16120 PROCwl(h%,"received="+STR$(got%)+" reads="+STR$(reads%)+" short="+STR$(short%)+" e1e="+STR$(e1e%)+" rmax="+STR$(rmax%))
16130 PROCwl(h%,"discarded d1="+STR$(d1%)+" d2="+STR$(d2%)+" d3="+STR$(d3%)+" lasta="+STR$(lasta%)+" lastg="+STR$(lastg%)+" rmax_now="+STR$(rmax%))
16140 PROCwl(h%,"busy_cs="+STR$(busy%)+" naps="+STR$(naps%)+" napn="+STR$(napn%))
16150 REM fb%, pit% and sz% are read ONCE at boot and cached for the whole
16160 REM session. If the Pi VDU driver ever reallocates the framebuffer, the
16170 REM engine keeps writing the old address and the display scans the new
16180 REM one - and the glass check cannot see it, because it reads through
16190 REM the same stale pointer. Re-read them here and compare.
16200 PROCwl(h%,"fb_cached=&"+STR$~fb%+" pit="+STR$(pit%)+" sz="+STR$(sz%))
16210 PROCwl(h%,"fb_now=&"+STR$~FNfbnow+" pit="+STR$(fbp%)+" sz="+STR$(fbs%))
16220 PROCwl(h%,"peeks="+STR$(peeks%)+" fellback="+STR$(fellback%)+" lasterr="+STR$~(lasterr%)+" peeknow="+STR$(peek%))
16230 PROCwl(h%,"send_dropped="+STR$(sdrop%)+" retries="+STR$(sretry%)+" worst="+STR$(smax%))
16240 PROCwl(h%,"[burst] pumps="+STR$(bursts%)+" bytes="+STR$(bbytes%)+" cs="+STR$(bcs%)+" reads="+STR$(breads%))
16250 IF bcs%>0 THEN PROCwl(h%,"  burst_rate="+STR$(bbytes%*100 DIV bcs%)+" bytes/sec")
16260 IF breads%>0 THEN PROCwl(h%,"  per_read us="+STR$(bcs%*10000 DIV breads%)+" bytes="+STR$(bbytes%*100 DIV breads%)+"/100")
16270 
16280 PROCwl(h%,"queue_depth_when_peeked qmax="+STR$(qmax%))
16290 PROCwl(h%,"  1-64="+STR$(q1%)+" 65-256="+STR$(q2%)+" 257-1024="+STR$(q3%)+" 1025-2048="+STR$(q4%)+" over2048="+STR$(q5%))
16300 
16310 IF busy%>0 THEN PROCwl(h%,"throughput="+STR$(got%*100 DIV busy%)+" bytes/sec")
16320 IF gcheck% THEN PROCwl(h%,"stale_cells="+STR$(gbad%))
16330 IF gcheck% THEN PROCwl(h%,"stale_cols="+FNhist(gcol%,cols%))
16340 IF gcheck% THEN PROCwl(h%,"stale_rows="+FNhist(grow%,rows%))
16350 IF gcheck% THEN PROCwl(h%,"stale_first="+STR$(gfirst%))
16360 IF gcheck% THEN PROCwl(h%,"stale_model x,y=glyph/fg/bg/flags")
16370 IF gcheck% THEN PROCwl(h%,gwhat$)
16380 IF gcheck% THEN PROCwl(h%,"stale_ops="+FNhist(gops%,32))
16390 IF gcheck% THEN PROCwl(h%,"glass_text="+gtxt$)
16400 IF gcheck% THEN PROCwl(h%,"glass_pixels x,y:8 rows of bits")
16410 IF gcheck% THEN PROCwl(h%,gpix$)
16420 PROCwl(h%,"[grid]")
16430 FOR y%=0 TO rows%-1:PROCwl(h%,FNrow(y%)):NEXT
16440 PROCwl(h%,"[odd]")
16450 FOR y%=0 TO rows%-1
16460   FOR x%=0 TO cols%-1
16470     IF FNcg(x%,y%)<32 OR FNcg(x%,y%)>126 THEN PROCwl(h%,STR$(y%)+" "+STR$(x%)+" "+STR$(FNcg(x%,y%)))
16480   NEXT
16490 NEXT
16500 PROCwl(h%,"[runs]")
16510 FOR y%=0 TO rows%-1:PROCruns(h%,y%):NEXT
16520 IF dbp%>0 THEN OSCLI("SAVE "+dump$+" "+STR$~db%+" +"+STR$~dbp%)
16530 ENDPROC
16540 :
16550 DEF PROCruns(h%,y%)
16560 LOCAL x%,s%,f%,b%,l%
16570 s%=0:f%=FNcf(0,y%):b%=FNcb(0,y%):l%=FNcl(0,y%)
16580 FOR x%=1 TO cols%-1
16590   IF FNcf(x%,y%)<>f% OR FNcb(x%,y%)<>b% OR FNcl(x%,y%)<>l% THEN PROCwl(h%,STR$(y%)+" "+STR$(s%)+" "+STR$(x%-s%)+" "+STR$(f%)+" "+STR$(b%)+" "+STR$(l%)):s%=x%:f%=FNcf(x%,y%):b%=FNcb(x%,y%):l%=FNcl(x%,y%)
16600 NEXT
16610 PROCwl(h%,STR$(y%)+" "+STR$(s%)+" "+STR$(cols%-s%)+" "+STR$(f%)+" "+STR$(b%)+" "+STR$(l%))
16620 ENDPROC
16630 :
16640 DEF FNrow(y%)
16650 LOCAL i%,c%
16660 FOR i%=0 TO cols%-1
16670   c%=FNcg(i%,y%)
16680   IF c%<32 OR c%>126 THEN c%=126
16690   dbuf%?i%=c%
16700 NEXT
16710 dbuf%?cols%=13
16720 =$dbuf%
16730 :
16740 DEF FNcg(x%,y%)
16750 =?(scr%+((y%*cols%+x%)*4))+(?(scr%+((y%*cols%+x%)*4)+1) AND 15)*256
16760 :
16770 DEF FNcf(x%,y%)
16780 =?(scr%+((y%*cols%+x%)*4)+2)
16790 :
16800 DEF FNcb(x%,y%)
16810 =?(scr%+((y%*cols%+x%)*4)+3)
16820 :
16830 DEF FNcl(x%,y%)
16840 =?(scr%+((y%*cols%+x%)*4)+1) DIV 16
16850 :
16860 REM Built in memory and saved in ONE operation. Written with BPUT# per
16870 REM byte the 7K dump took FIVE SECONDS over LANManFS - the same 58ms a
16880 REM byte that phase 3 measured for BGET# - and every one of those
16890 REM seconds was after CTRL-] had been pressed, so the terminal looked
16900 REM like it had hung on the way out.
16910 REM WARNING: h% IS IGNORED. This writes into the in-memory dump buffer,
16920 REM not to a file - PROCef is the one that takes a handle. The signature
16930 REM lies, and it has now cost two bugs: PROCfail wrote nowhere once, and
16940 REM the profiler wrote every snapshot into this buffer instead of
16950 REM RESPROF, which came out zero bytes.
16960 DEF PROCwl(h%,s$)
16970 LOCAL i%
16980 FOR i%=1 TO LEN(s$)
16990   IF dbp%<dbmax% THEN db%?dbp%=ASC(MID$(s$,i%,1)):dbp%=dbp%+1
17000 NEXT
17010 IF dbp%<dbmax%-1 THEN db%?dbp%=13:db%?(dbp%+1)=10:dbp%=dbp%+2
17020 ENDPROC
17030 :
17040 DEF PROCsa
17050 LOCAL i%,a%,b%,o%
17060 FOR i%=0 TO 15:sa%?i%=0:NEXT
17070 sa%?0=16:sa%?1=AFINET%
17080 sa%?2=port% DIV 256:sa%?3=port% MOD 256
17090 a%=1:o%=4
17100 FOR i%=1 TO 4
17110   b%=INSTR(host$+".",".",a%)
17120   sa%?o%=VAL(MID$(host$,a%,b%-a%))
17130   a%=b%+1:o%=o%+1
17140 NEXT
17150 ENDPROC
17160 :
17170 DEF PROCzero
17180 LOCAL i%
17190 FOR i%=0 TO 27:blk%?i%=0:NEXT
17200 blk%?0=28:blk%?1=28:blk%?3=0
17210 ENDPROC
17220 :
17230 REM There is no CALL &FFF1 on ARM. PTRTEST2 confirmed on copro 15 that
17240 REM SYS "OS_Word" reaches the module and that the buffers behind the
17250 REM pointers cross the Tube in both directions.
17260 DEF PROCosw
17270 SYS "OS_Word",&C0,blk%
17280 ENDPROC
17290 :
17300 REM +2 holds the command on entry and a module that services the call
17310 REM zeroes it. A SURVIVING +2 means nothing claimed it - and then no
17320 REM field is touched at all, so +3 reads 0 because it started 0 and an
17330 REM unclaimed call is indistinguishable from success (5.5c).
17340 DEF PROCchk(w$)
17350 IF blk%?2<>0 THEN PROCstop("no socket module ("+w$+")")
17360 IF blk%?3<>0 THEN PROCstop("cannot "+w$+", r=&"+STR$~blk%?3)
17370 ENDPROC
17380 :
17390 DEF PROCdead
17400 quit%=TRUE
17410 ENDPROC
17420 :
17430 DEF PROCtidy
17440 *FX4,0
17450 *FX229,0
17452 REM CAPS LOCK BACK ON for the Beeb, whose own world - BASIC keywords,
17454 REM MOS commands, filenames - is upper case. THE BITS ARE INVERTED:
17455 REM the Advanced User Guide 14.12 says bit 4 is 0 WHEN CAPS LOCK IS
17456 REM ENGAGED. So 48 is both locks OFF and 32 is CAPS ON, which is the
17457 REM opposite of the obvious guess. OSBYTE 118 makes the LED agree.
17458 *FX202,32
17459 *FX118
17460 ENDPROC
17470 :
17480 DEF PROCstop(s$)
17490 PROCtidy
17500 VDU 23,1,1:VDU 26:CLS
17510 PRINT "PTERM: ";s$
17520 END
17530 :
17540 REM The error goes to the SHARE as well as the screen. An error message
17550 REM on the Pi display is something a person has to read off a monitor
17560 REM and retype, and the state that produced it - where the cursor was,
17570 REM what mode the parser was in, how much had been received - is gone
17580 REM the moment it is printed.
17590 REM PROCwl writes into the dump BUFFER now, not to a handle, so the
17600 REM error report was being built in memory and thrown away - errors
17610 REM have been going nowhere since the dump was buffered. It writes the
17620 REM file itself here, a byte at a time, because an error handler must
17630 REM not depend on anything else still working.
17640 DEF PROCfail
17650 LOCAL h%,i%,s$
17660 PROCtidy
17670 h%=OPENOUT(err$)
17680 IF h%<>0 THEN PROCerrf(h%):CLOSE#h%
17690 VDU 26,23,1,1
17700 CLS
17710 PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
17720 REPORT:PRINT
17730 PRINT "written to ";err$
17740 END
17750 :
17760 DEF PROCerrf(h%)
17770 PROCef(h%,"[ptermerr1]")
17780 PROCef(h%,"err="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
17790 PROCef(h%,"cursor="+STR$(cx%)+","+STR$(cy%)+" pw="+STR$(pw%))
17800 PROCef(h%,"region="+STR$(top%)+"-"+STR$(bot%)+" origin="+STR$(dom%))
17810 PROCef(h%,"sgr fg="+STR$(sf%)+" bg="+STR$(sb%)+" flags="+STR$(sfl%))
17820 PROCef(h%,"parser vst="+STR$(vst%)+" u8n="+STR$(u8n%)+" np="+STR$(np%)+" prv="+STR$(prv%))
17830 PROCef(h%,"alt="+STR$(alton%)+" altbuf=&"+STR$~alt%+" awm="+STR$(awm%)+" ins="+STR$(ins%))
17840 PROCef(h%,"telnet tstate="+STR$(tstate%)+" tverb="+STR$(tverb%))
17850 PROCef(h%,"socket="+STR$(sock%)+" rsz="+STR$(rsz%))
17860 REM Nothing risky in here. An error handler that raises its own error
17870 REM loses the report it was written to preserve, so no pseudo-variable
17880 REM that might not exist on the BASIC of the day.
17890 PROCef(h%,"[end]")
17900 ENDPROC
17910 REM Straight to the file. No buffer, no dependency on the dump.
17920 DEF PROCef(h%,s$)
17930 LOCAL i%
17940 FOR i%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,i%,1)):NEXT
17950 BPUT#h%,13:BPUT#h%,10
17960 ENDPROC
17970 :
17980 REM The glass cell decoded back to a character, or ? when it matches no
17990 REM glyph at all - which would itself be informative, meaning the pixels
18000 REM are not a character.
18010 DEF FNglyph(x%,y%)
18020 LOCAL l%,i%,b%,q%,c%,bg%,ok%
18030 bg%=?(scr%+(y%*cols%+x%)*4+3)
18040 FOR l%=0 TO ch%-1
18050   q%=gc%+(y%*ch%+l%)*pit%+x%*cw%
18060   b%=0
18070   FOR i%=0 TO cw%-1
18080     IF q%?i%<>bg% THEN b%=b%+2^(cw%-1-i%)
18090   NEXT
18100   gb%?l%=b%
18110 NEXT
18120 FOR c%=32 TO 126
18130   ok%=TRUE
18140   FOR l%=0 TO ch%-1
18150     IF gb%?l%<>font%?(c%*ch%+l%) THEN ok%=FALSE
18160   NEXT
18170   IF ok% THEN =CHR$(c%)
18180 NEXT
18190 ="?"
18200 REM Re-reads the framebuffer geometry from the driver. Sets fbp%/fbs%
18210 REM as a side effect so one SYS answers all three.
18220 DEF FNfbnow
18230 LOCAL q2%,r2%
18240 fbp%=0:fbs%=0
18250 IF sim% OR fb%=0 THEN =0
18260 DIM q2% 31,r2% 31
18270 !q2%=148:q2%!4=150:q2%!8=6:q2%!12=-1
18280 SYS "OS_ReadVduVariables",q2%,r2%
18290 fbp%=r2%!8:fbs%=r2%!4
18300 =!r2%
18310 REM ================ SSH transport ================
18320 REM
18330 REM Five hooks above and this block. The engine, the VT parser, the drain
18340 REM loop, the keyboard and the flush are untouched: SSH replaces the
18350 REM TRANSPORT, not the terminal. Every hook is one line and every one of
18360 REM them is a no-op when ssh% is FALSE, so the telnet path of 3.5 still
18370 REM works and is still the fallback.
18380 REM
18390 REM The socket stays OURS. src/ssh/ssh.h does no I/O at all - it is handed
18400 REM ciphertext and asked for plaintext - which is why 5.5a's short reads
18410 REM and 5.5c's 64-byte cap still govern FNraw_recv below, unchanged.
18420 REM PROCsshcfg IS CALLED LAST, NOT FIRST, AND THAT IS THE POINT. It
18430 REM once ran before host$/port% were set, so its port%=22 was
18440 REM overwritten by the port%=2323 below it - and the terminal
18450 REM dialled the telnet gateway's port and said "cannot connect &1E".
18460 DEF PROCsshcfg
18470 ssh%=TRUE
18480 IF NOT ssh% THEN ENDPROC
18490 port%=22
18500 sshu$="user":sshk$="SSHKEY":sshf$="SSHBLOB"
18510 sshc%=1
18520 sshb%=&4100000:sshp%=&4200000
18530 sshlen%=50244:sshsum%=5958089:sshver%=&5B1CE003:REM BUILDSTAMP-SSH
18540 ENDPROC
18550 :
18560 REM Loads the blob, checks it, authenticates and pumps until the shell is
18570 REM open, all before PROCmain runs - so the terminal starts on a session
18580 REM rather than on a connection. Measured at about 1.4 seconds.
18590 DEF PROCssh_open
18600 LOCAL i%,s%,st%,t0%
18610 sshb%?0=0:sshb%?(sshlen%-1)=0
18620 OSCLI("LOAD "+sshf$+" "+STR$~sshb%)
18630 s%=0:FOR i%=0 TO sshlen%-1:s%=s%+sshb%?i%:NEXT
18640 IF s%<>sshsum% THEN PROCstop("SSHBLOB sum "+STR$(s%)+" not "+STR$(sshsum%))
18650 A%=10:IF USR(sshb%)<>sshver% THEN PROCstop("SSHBLOB is the wrong build")
18660 OSCLI("LOAD "+sshk$+" "+STR$~sshkey%)
18670 sshp%!4=sshc%
18680 A%=1:IF USR(sshb%)<>0 THEN PROCstop("no entropy from the SoC RNG")
18690 PROCsshstr(sshnm%,sshu$)
18700 sshp%!4=sshnm%:sshp%!8=sshkey%:sshp%!12=sshkey%+32
18710 A%=2:IF USR(sshb%)<>0 THEN PROCsshbad
18720 PROCssh_size
18730 t0%=TIME
18740 REPEAT
18750   PROCssh_drain
18760   s%=FNraw_recv
18770   IF s%>0 THEN PROCssh_feed(s%)
18780   A%=8:st%=USR(sshb%)
18785 IF st%=13 THEN PROCaskhost
18789 IF st%=12 THEN PROCaskpass
18790 UNTIL st%=9 OR st%=10 OR (TIME-t0%)>3000
18800 IF st%<>9 THEN PROCsshbad
18810 PROCssh_drain
18820 ENDPROC
18830 :
18840 DEF PROCssh_size
18850 sshp%!4=cols%:sshp%!8=rows%
18860 A%=3:sshr%=USR(sshb%)
18870 ENDPROC
18880 :
18890 REM BBC BASIC's $ terminates with CR, not NUL. Handing $nm% straight to C
18900 REM sent a user name with a carriage return on the end, and the server
18910 REM refused the key with the whole key exchange having succeeded.
18920 DEF PROCsshstr(p%,s$)
18930 LOCAL i%
18940 FOR i%=1 TO LEN(s$):p%?(i%-1)=ASC(MID$(s$,i%,1)):NEXT
18950 p%?LEN(s$)=0
18960 ENDPROC
18970 :
18980 DEF PROCsshbad
18990 LOCAL p%,e$,c%
19000 A%=9:p%=USR(sshb%)
19010 e$=""
19020 REPEAT
19030   c%=p%?LEN(e$)
19040   IF c%>0 THEN e$=e$+CHR$(c%)
19050 UNTIL c%=0 OR LEN(e$)>90
19060 PROCstop("ssh: "+e$)
19070 ENDPROC
19080 :
19090 DEF PROCssh_feed(n%)
19100 sshp%!4=crx%:sshp%!8=n%
19110 A%=4:IF USR(sshb%)<>0 THEN PROCsshbad
19120 ENDPROC
19130 :
19140 REM Everything the core wants sent, out through the module.
19150 DEF PROCssh_drain
19160 LOCAL n%
19170 REPEAT
19180   sshp%!4=stx%:sshp%!8=4096
19190   A%=5:n%=USR(sshb%)
19200   IF n%>0 THEN PROCraw_send(n%)
19210 UNTIL n%=0
19220 ENDPROC
19230 :
19240 REM THE RULES OF 5.5a AND 5.5c APPLY UNCHANGED, and under SSH they stop
19250 REM being performance tuning and become the protocol's correctness
19260 REM condition: a read above ~64 bytes is refused AND CONSUMES WHAT IT
19270 REM REFUSES. Under telnet that lost 111 bytes and printed an escape
19280 REM sequence as text; under SSH it is a Poly1305 failure and a dead
19290 REM session, every time.
19300 DEF FNraw_recv
19310 LOCAL g%
19320 reads%=reads%+1
19330 blk%?0=20:blk%?1=8:blk%?2=&05:blk%?3=0
19340 blk%!4=sock%:blk%!8=crx%:blk%!12=rmax%:blk%!16=mnowait%
19350 PROCosw
19360 IF blk%?2<>0 THEN PROCdead:=0
19370 IF blk%?3=&1E THEN e1e%=e1e%+1:=0
19380 IF blk%?3<>0 THEN PROCnopeek(blk%?3):=0
19390 g%=blk%!4
19400 IF g%=0 THEN PROCclosed:=0
19410 IF g%<1 THEN =0
19420 IF g%>rmax% THEN d1%=d1%+1:lasta%=g%:=0
19430 =g%
19440 :
19450 REM Ciphertext in, plaintext out. The drain comes FIRST so a window adjust
19460 REM the last pass produced is on its way before this one asks for more.
19470 DEF FNssh_recv
19480 LOCAL n%
19490 PROCssh_drain
19500 n%=FNraw_recv
19510 IF n%>0 THEN PROCssh_feed(n%)
19520 sshp%!4=rx%:sshp%!8=4096
19530 A%=6:n%=USR(sshb%)
19531 IF FNssh_state=11 THEN PROCclosed
19540 =n%
19550 :
19560 REM Keystrokes go in as plaintext and come out as a packet. The core
19570 REM refuses when the server's channel window is closed - the flow control
19580 REM full-screen-apps.md wanted and could not get from XOFF, because it
19590 REM lives below the application and ncurses cannot switch it off.
19600 DEF PROCssh_send(n%)
19610 LOCAL i%
19620 IF n%<1 THEN ENDPROC
19630 FOR i%=0 TO n%-1:stx%?i%=tx%?i%:NEXT
19640 sshp%!4=stx%:sshp%!8=n%
19650 A%=7:IF USR(sshb%)<>0 THEN sdrop%=sdrop%+n%
19660 PROCssh_drain
19670 ENDPROC
19680 :
19690 REM Thirty tries, not two hundred: at 3.28ms a call two hundred is two
19700 REM thirds of a second of unbreakable stall per key, and the machine was
19710 REM reported locking up while typing after a heavy burst.
19720 DEF PROCraw_send(n%)
19730 LOCAL s%,g%,t%
19740 s%=0:t%=0
19750 REPEAT
19760   PROCzero:blk%?2=&08
19770   blk%!4=sock%:blk%!8=stx%+s%:blk%!12=n%-s%:blk%!16=mnowait%
19780   PROCosw
19790   IF blk%?2<>0 THEN PROCdead
19800   g%=0
19810   IF blk%?3=0 THEN g%=blk%!4
19820   IF g%>0 THEN s%=s%+g%
19830   IF g%<1 THEN t%=t%+1
19840 UNTIL s%>=n% OR t%>sendtry% OR quit%
19850 IF s%<n% THEN sdrop%=sdrop%+(n%-s%)
19860 ENDPROC
19870 :
19880 REM 11 is SSH_ST_CLOSED: the far end ended the session, which is what
19890 REM typing exit at the shell does. It is NOT an error. Routing it
19900 REM through PROCsshbad ended the program via PROCstop, which skips the
19910 REM profile, the glass check and the rlog - so the same keystroke wrote
19920 REM the files or did not, depending on whether CHANNEL_CLOSE or the TCP
19930 REM close arrived first.
19940 DEF FNssh_state
19950 LOCAL s%
19960 A%=8:s%=USR(sshb%)
19970 =s%
19980 REM ================ destination prompt ================
19990 REM
20000 REM Asked BEFORE PROCv_boot, so it uses the BBC's own screen with a plain
20010 REM INPUT. After the engine boots, a PRINT goes through the Pi VDU driver
20020 REM onto cells the model believes are blank, and the shadow then agrees
20030 REM they need no painting - so the flush could never remove them. Line
20040 REM editing works here too, because *FX4,1 has not run yet.
20050 REM
20060 REM A NAME IS RESOLVED, not just a dotted quad. PROCsa parses host$ with
20070 REM VAL on four dot-separated parts, so "deskbox" would have become
20080 REM 0.0.0.0 and connected to nothing, with no error worth reading. The
20090 REM module has a resolver - OSWORD &C0 command &40, section 4 - and it is
20100 REM one call.
20106 REM CAPS LOCK IS TURNED OFF AT LINE 600, BEFORE THIS RUNS, and it
20107 REM used to be turned off at 704, after. Host names and user names
20108 REM are case-sensitive and FNhost matches HOSTS exactly, so a prompt
20109 REM answered in capitals asked for MINI and PAUL and found neither.
20110 DEF PROCask
20120 LOCAL a$
20130 PRINT
20140 PRINT "PTERM destination - RETURN keeps the default"
20150 PRINT
20160 PRINT "  host [";host$;"] ";
20170 INPUT ""a$
20180 IF a$<>"" THEN host$=a$
20190 IF ssh% THEN PRINT "  user [";sshu$;"] ";:INPUT ""a$:IF a$<>"" THEN sshu$=a$
20200 PRINT "  port [";port%;"] ";
20210 INPUT ""a$
20220 IF a$<>"" THEN port%=VAL(a$)
20230 IF NOT FNdotted(host$) THEN PROCname
20240 PRINT
20250 PRINT "connecting to ";host$;":";port%;
20260 IF ssh% THEN PRINT " as ";sshu$ ELSE PRINT
20270 ENDPROC
20280 :
20290 REM Four dot-separated parts, each 0-255 and each actually a number. VAL
20300 REM returns 0 for anything it cannot read, so "deskbox" would sail
20310 REM through a test that only checked ranges.
20320 REM
20330 REM NO EARLY EXIT FROM INSIDE A LOOP. Leaving a function with = while a
20340 REM FOR is open leaves its stack entry behind, and the tidy-looking first
20350 REM version had five such exits. Both loops below always reach their NEXT
20360 REM and the answer is carried in a flag.
20370 DEF FNdotted(s$)
20380 LOCAL i%,c$,dots%,ok%,a%,b%,p$
20390 ok%=TRUE:dots%=0
20400 FOR i%=1 TO LEN(s$)
20410   c$=MID$(s$,i%,1)
20420   IF c$="." THEN dots%=dots%+1
20430   IF c$<>"." AND INSTR("0123456789",c$)=0 THEN ok%=FALSE
20440 NEXT
20450 IF dots%<>3 THEN ok%=FALSE
20460 a%=1
20470 FOR i%=1 TO 4
20480   b%=INSTR(s$+".",".",a%)
20490   p$=""
20500   IF b%>0 THEN p$=MID$(s$,a%,b%-a%)
20510   IF p$="" OR LEN(p$)>3 THEN ok%=FALSE
20520   IF p$<>"" THEN IF VAL(p$)>255 THEN ok%=FALSE
20530   IF b%>0 THEN a%=b%+1
20540 NEXT
20550 IF a%<=LEN(s$) THEN ok%=FALSE
20560 =ok%
20570 :
20580 REM ================ names ================
20590 REM
20600 REM THE MODULE RESOLVES PERFECTLY WELL - *MOUNT \\deskbox\\beeb works with
20610 REM no HOSTS file at all. What failed was reading the ANSWER:
20620 REM Resolver_GetHostByName returns +20 as a pointer to a list of pointers in
20630 REM the I/O processor's memory, and dereferencing that on the ARM reads
20640 REM CO-PROCESSOR memory at the same address. It gave 32.32.32.32 when the
20650 REM call was written wrongly and 0 when it was written correctly, and both
20660 REM times the call itself had succeeded: +12 came back 2 for AF_INET and
20670 REM +16 came back 4 for IPv4.
20680 REM
20690 REM 5.5c's "pointers cross the Tube" is about buffers WE supply, which the
20700 REM Tube protocol copies. A pointer the module hands back is a host address
20710 REM and nothing carries the bytes behind it.
20720 REM
20730 REM OSWORD 5 IS EXACTLY THAT MECHANISM. The Advanced User Guide 18.9: a
20740 REM five-byte block holding a four-byte i/o processor address, and the byte
20750 REM read comes back in the last byte. Two indirections is eight of them.
20760 DEF FNpeek(a%)
20770 !pk%=a%
20780 SYS "OS_Word",5,pk%
20790 =pk%?4
20800 :
20810 REM A host pointer, low byte first. The top two bytes must be zero - an i/o
20820 REM processor address is 16-bit - and -1 says they were not, which would
20830 REM mean the field is not the pointer this code thinks it is.
20840 DEF FNpeek2(a%)
20850 IF FNpeek(a%+2)<>0 OR FNpeek(a%+3)<>0 THEN =-1
20860 =FNpeek(a%)+FNpeek(a%+1)*256
20870 :
20880 REM Resolver_GetHostByName (&40), per docs/netprogapi.pdf. ENTRY: +8 points
20890 REM at the name. EXIT: +12 is the address type, +16 the length, +20 a
20900 REM pointer to a null-terminated list of pointers to addresses. +12 and +16
20910 REM are OUTPUTS - specification.md section 4's table says otherwise and is
20920 REM wrong for this call, which is what cost the first two attempts.
20930 DEF FNresolve(n$)
20940 LOCAL r$
20950 rwhy$=""
20960 r$=FNresolve1(n$)
20970 IF r$<>"" THEN =r$
20980 IF dom$="" OR INSTR(n$,".")>0 THEN =""
20990 REM THE MODULE DOES NOT APPEND A SEARCH DOMAIN. "archbox" resolves on a Linux
21000 REM box only because resolv.conf says "search lan" and the query that
21010 REM actually goes out is archbox.lan; the module asks for what it is given and
21020 REM gets nothing back. So ask again with dom$ on the end, which is what the
21030 REM other machine was doing all along.
21040 r$=FNresolve1(n$+"."+dom$)
21050 IF r$<>"" THEN rwhy$=""
21060 =r$
21070 :
21080 REM One query. rwhy$ says which step failed, because returning "" from six
21090 REM different places and printing "did not resolve" is how the last three
21100 REM attempts at this call were debugged by guesswork.
21110 DEF FNresolve1(n$)
21120 LOCAL lp%,ap%,a%,b%,c%,d%
21130 PROCsshstr(nm2%,n$)
21140 PROCzero
21150 blk%?2=&40
21160 blk%!8=nm2%
21170 PROCosw
21180 IF blk%?2<>0 THEN rwhy$="no socket module":=""
21190 IF blk%?3<>0 THEN rwhy$=n$+": resolver error &"+STR$~blk%?3:=""
21200 IF blk%!12<>2 THEN rwhy$="address type "+STR$(blk%!12)+", not AF_INET":=""
21210 IF blk%!16<>4 THEN rwhy$="address length "+STR$(blk%!16)+", not IPv4":=""
21220 lp%=blk%!20
21230 IF lp%<=0 THEN rwhy$="no address list":=""
21240 ap%=FNpeek2(lp%)
21250 IF ap%=-1 THEN rwhy$="list pointer is not a 16-bit host address":=""
21260 IF ap%=0 THEN rwhy$="address list is empty":=""
21270 a%=FNpeek(ap%):b%=FNpeek(ap%+1):c%=FNpeek(ap%+2):d%=FNpeek(ap%+3)
21280 IF a%=0 THEN rwhy$="first address reads 0.0.0.0":=""
21290 =STR$(a%)+"."+STR$(b%)+"."+STR$(c%)+"."+STR$(d%)
21300 DEF FNhost(n$)
21310 LOCAL h%,c%,l$
21320 hfound$="":htarget$=n$
21330 h%=OPENIN("HOSTS")
21340 IF h%=0 THEN =""
21350 REPEAT
21360   l$=""
21370   REPEAT
21380     c%=BGET#h%
21390     IF c%>=32 THEN l$=l$+CHR$(c%)
21400   UNTIL c%<32 OR EOF#h%
21410   PROCmatch(l$)
21420 UNTIL EOF#h%
21430 CLOSE#h%
21440 =hfound$
21450 :
21460 REM One line of the file. A PROC rather than inline because FNhost is
21470 REM already two REPEATs deep, and leaving a loop early to return a value is
21480 REM how a FOR or REPEAT stack entry gets left behind.
21490 DEF PROCmatch(l$)
21500 LOCAL s%,ip$,nm$,w$
21510 IF LEFT$(l$,1)="#" THEN ENDPROC
21520 s%=INSTR(l$," ")
21530 IF s%=0 THEN ENDPROC
21540 ip$=LEFT$(l$,s%-1)
21550 nm$=MID$(l$,s%+1)
21560 REPEAT
21570   REPEAT
21580     IF LEFT$(nm$,1)=" " THEN nm$=MID$(nm$,2)
21590   UNTIL nm$="" OR LEFT$(nm$,1)<>" "
21600   s%=INSTR(nm$," ")
21610   IF s%=0 THEN w$=nm$:nm$="" ELSE w$=LEFT$(nm$,s%-1):nm$=MID$(nm$,s%+1)
21620   IF w$<>"" AND w$=htarget$ THEN hfound$=ip$
21630 UNTIL nm$=""
21640 ENDPROC
21650 REM A name that is not in HOSTS is not fatal - it re-asks, because the
21660 REM alternative is ending the program over a typo. PROCstop on a bad host
21670 REM would mean reloading 107KB of PTERMRUN to try again.
21680 REM HOSTS first, then the module's resolver - the same order a Unix box
21690 REM uses, and for the same reason: the file is the local override. A name
21700 REM that is in neither re-asks rather than stopping, because ending the
21710 REM program over a typo means reloading 107KB of PTERMRUN to try again.
21720 DEF PROCname
21730 LOCAL ip$,w$
21740 REPEAT
21750   w$=host$
21760   ip$=FNhost(w$)
21770   IF ip$="" THEN ip$=FNresolve(w$)
21780   IF ip$="" THEN PROCnotfound
21790 UNTIL ip$<>"" OR FNdotted(host$)
21800 IF ip$<>"" THEN host$=ip$:PRINT "  ";w$;" is ";host$
21810 ENDPROC
21820 :
21830 DEF PROCnotfound
21840 LOCAL a$
21850 PRINT "  ";host$;" is in neither HOSTS nor DNS."
21860 IF rwhy$<>"" THEN PRINT "  resolver: ";rwhy$
21870 PRINT "  Give an address, or add a"
21880 PRINT "  line to HOSTS on the share: 192.0.2.60 archbox"
21890 PRINT "  host [";host$;"] ";
21900 INPUT ""a$
21910 IF a$<>"" THEN host$=a$
21920 ENDPROC
21930 REM State 12 is SSH_ST_NEEDPASS: the key was refused and the core is
21940 REM waiting to be given a password, because only this side has a keyboard.
21950 REM ssh itself behaves the same way - the key is tried first and in the
21960 REM usual case no password is sent at all.
21970 REM
21980 REM THROUGH THE ENGINE, not PRINT. This runs after PROCv_boot, so a plain
21990 REM PRINT would paint cells the model believes are blank and the flush
22000 REM could never remove them.
22010 REM
22020 REM t0% belongs to PROCssh_open and is reset here on purpose: typing a
22030 REM password can easily outlast a thirty-second handshake timeout, and the
22040 REM timeout is there to catch a silent server, not a slow typist.
22050 DEF PROCaskpass
22060 LOCAL p$,k%,n%
22070 PROCv_writes(CHR$(13)+CHR$(10)+"password for "+sshu$+"@"+host$+": ")
22080 n%=FNv_flush
22090 p$=""
22100 REPEAT
22110   k%=GET
22120   IF k%=127 AND LEN(p$)>0 THEN p$=LEFT$(p$,LEN(p$)-1):PROCv_writes(CHR$(8)+" "+CHR$(8))
22130   IF k%>=32 AND k%<127 AND LEN(p$)<120 THEN p$=p$+CHR$(k%):PROCv_writes("*")
22140   n%=FNv_flush
22150 UNTIL k%=13 OR k%=27
22160 PROCv_writes(CHR$(13)+CHR$(10))
22170 n%=FNv_flush
22180 IF k%=27 THEN PROCstop("cancelled")
22190 PROCsshstr(pw%,p$)
22200 p$=""
22210 sshp%!4=pw%
22220 A%=11:IF USR(sshb%)<>0 THEN PROCsshbad
22230 PROCwipe(pw%,127)
22240 t0%=TIME
22250 ENDPROC
22260 :
22270 REM The core wipes its own copy the moment the password is in the packet.
22280 REM This is the other copy, and BASIC cannot clear a string, which is why
22290 REM the password goes through a byte buffer rather than staying in p$.
22300 DEF PROCwipe(a%,n%)
22310 LOCAL i%
22320 FOR i%=0 TO n%:a%?i%=0:NEXT
22330 ENDPROC
22340 :
22350 REM ================ the host key, and remembering it ================
22360 REM
22370 REM State 13 is SSH_ST_NEEDHOST. The core has checked the host key's
22380 REM SIGNATURE - the server holds the private half of what it showed - and
22390 REM stopped, because that says nothing about it being the RIGHT host. Any
22400 REM impostor's own key passes the same test. Only this side can decide, so
22410 REM the core waits here exactly as it waits at 12 for a password.
22420 REM
22430 REM WHAT THIS BUYS. Without it a machine answering on archbox's address would
22440 REM be handed the password. With it, a changed key stops the session before
22450 REM a keystroke is sent.
22460 REM
22470 REM KNOWNHST is /etc/hosts shaped and CR-terminated, like HOSTS beside it:
22480 REM
22490 REM   archbox SHA256:<example>
22500 REM
22510 REM KEYED ON THE ADDRESS, not on what was typed: PROCname has already
22520 REM replaced host$ with the dotted quad by the time this runs, so archbox and
22530 REM 192.0.2.30 are one entry rather than two. ssh keys on both and warns
22531 REM when they disagree; this side cannot, because by here the name is gone.
22532 REM The cost is that a machine which changes address looks like a new host,
22533 REM and one that inherits an address looks like a changed key.
22540 DEF PROCaskhost
22550 LOCAL p%,c%,fp$,k$,a$,n%
22560 A%=12:p%=USR(sshb%)
22570 fp$=""
22580 REPEAT
22590   c%=p%?LEN(fp$)
22600   IF c%>0 THEN fp$=fp$+CHR$(c%)
22610 UNTIL c%=0 OR LEN(fp$)>60
22620 IF fp$="" THEN PROCstop("ssh: no host key to check")
22630 k$=FNknown(host$)
22640 IF k$=fp$ THEN PROCkeyok:ENDPROC
22650 IF k$<>"" THEN PROCkeybad(k$,fp$)
22660 PROCv_writes(CHR$(13)+CHR$(10)+"unknown host "+host$)
22670 PROCv_writes(CHR$(13)+CHR$(10)+"key "+fp$)
22680 PROCv_writes(CHR$(13)+CHR$(10)+"compare that against ssh-keygen -lf on the far end.")
22690 PROCv_writes(CHR$(13)+CHR$(10)+"type yes to trust it and remember it: ")
22700 n%=FNv_flush
22710 a$=FNaskline
22720 IF a$<>"yes" THEN PROCstop("host key not accepted")
22730 PROCsavekey(host$,fp$)
22740 PROCkeyok
22750 ENDPROC
22760 :
22770 REM t0% belongs to PROCssh_open and is reset for the same reason PROCaskpass
22780 REM resets it: reading a fingerprint off two screens outlasts a thirty-second
22790 REM handshake timeout, and that timeout is there to catch a silent server.
22800 DEF PROCkeyok
22810 LOCAL n%
22820 A%=13:n%=USR(sshb%)
22830 IF n%<>0 THEN PROCstop("ssh: the core would not accept the host key")
22840 t0%=TIME
22850 ENDPROC
22860 :
22870 REM No prompt and no way to continue. A key that has changed is either a
22880 REM machine that was rebuilt or someone standing in the middle, and this side
22890 REM cannot tell which - so it stops, and says what to delete if it was the
22900 REM first.
22910 DEF PROCkeybad(was$,now$)
22920 LOCAL n%
22930 PROCv_writes(CHR$(13)+CHR$(10)+"HOST KEY CHANGED for "+host$)
22940 PROCv_writes(CHR$(13)+CHR$(10)+"expected "+was$)
22950 PROCv_writes(CHR$(13)+CHR$(10)+"     got "+now$)
22960 PROCv_writes(CHR$(13)+CHR$(10)+"if that machine was rebuilt, delete its line from KNOWNHST.")
22970 n%=FNv_flush
22980 PROCstop("host key changed for "+host$)
22990 ENDPROC
23000 :
23010 REM Echoed, unlike the password. There is nothing secret in "yes" and a
23020 REM prompt that swallows what is typed is a prompt people answer twice.
23030 DEF FNaskline
23040 LOCAL a$,k%,n%
23050 a$=""
23060 REPEAT
23070   k%=GET
23080   IF k%=127 AND LEN(a$)>0 THEN a$=LEFT$(a$,LEN(a$)-1):PROCv_writes(CHR$(8)+" "+CHR$(8))
23090   IF k%>=32 AND k%<127 AND LEN(a$)<20 THEN a$=a$+CHR$(k%):PROCv_writes(CHR$(k%))
23100   n%=FNv_flush
23110 UNTIL k%=13
23120 =a$
23130 :
23140 REM The remembered key for a host, or "" if it has never been seen. Same
23150 REM shape as FNhost above, and the same reason for the flag rather than an
23160 REM early return: leaving a REPEAT through = leaves its stack entry behind.
23170 DEF FNknown(n$)
23180 LOCAL h%,c%,l$,r$
23190 r$=""
23200 h%=OPENIN("KNOWNHST")
23210 IF h%=0 THEN =""
23220 REPEAT
23230   l$=""
23240   REPEAT
23250     c%=BGET#h%
23260     IF c%>=32 THEN l$=l$+CHR$(c%)
23270   UNTIL c%<32 OR EOF#h%
23280   IF LEFT$(l$,LEN(n$)+1)=n$+" " THEN r$=MID$(l$,LEN(n$)+2)
23290 UNTIL EOF#h%
23300 CLOSE#h%
23310 =r$
23320 :
23330 REM Appended, never rewritten: OPENUP and seek to the end. Rewriting the
23340 REM whole file to add one line is how a power cut loses the other hosts.
23350 DEF PROCsavekey(n$,f$)
23360 LOCAL h%,i%,l$
23370 l$=n$+" "+f$
23380 h%=OPENUP("KNOWNHST")
23390 IF h%=0 THEN h%=OPENOUT("KNOWNHST")
23400 IF h%=0 THEN PROCv_writes(CHR$(13)+CHR$(10)+"(could not write KNOWNHST)"):ENDPROC
23410 PTR#h%=EXT#h%
23420 FOR i%=1 TO LEN(l$):BPUT#h%,ASC(MID$(l$,i%,1)):NEXT
23430 BPUT#h%,13
23440 CLOSE#h%
23450 ENDPROC
23460 :
23470 REM ---- connect, and what &1E means here ----
23480 REM
23490 REM &1E IS NOT A REFUSAL. specification.md 5.5c has it as "cannot satisfy
23500 REM the request", and on a connect that is the SYN going unanswered - the
23510 REM far end dropping it rather than sending a RST. A machine that answers
23520 REM *PING and has no sshd looks exactly like this, and PTERM used to stop
23530 REM dead on the first one with "cannot connect, r=&1E", which reads like a
23540 REM fault in the terminal rather than a fact about the far end.
23550 REM
23560 REM specification.md 3 already records the same trap costing a run, and
23570 REM says why it was never caught: "ptrtest2 connects at tries=1, so the
23580 REM retry was never exercised". This is that retry.
23590 REM
23600 REM A refusal (anything that is not &1E) is reported at once. There is no
23610 REM point retrying a RST - it will arrive again just as fast.
23611 REM
23612 REM NOT TESTED, AND WORTH KNOWING WHERE TO LOOK: this retries on the SAME
23613 REM socket. Berkeley says a socket whose connect has failed should be
23614 REM closed and remade, and whether this module cares is unmeasured - the
23615 REM machine that prompted this has nothing listening, so every attempt
23616 REM fails either way and the question cannot be settled on it. If a slow
23617 REM host still fails after eight tries, remaking the socket inside the
23618 REM loop is the next thing to try.
23620 DEF PROCconnect
23630 LOCAL i%,t0%
23640 FOR i%=1 TO 8
23650   PROCzero:blk%?2=&04
23660   blk%!4=sock%:blk%!8=sa%:blk%!12=16
23670   PROCosw
23680   IF blk%?2<>0 THEN PROCstop("no socket module (connect)")
23690   IF blk%?3=0 THEN i%=8
23700   IF blk%?3<>0 AND blk%?3<>&1E THEN i%=8
23710   IF blk%?3=&1E AND i%<8 THEN t0%=TIME:REPEAT UNTIL TIME-t0%>=25
23720 NEXT
23730 IF blk%?3=0 THEN ENDPROC
23740 IF blk%?3=&1E THEN PROCstop("nothing answered at "+host$+":"+STR$(port%)+" - is a server listening?")
23750 PROCstop("cannot connect to "+host$+":"+STR$(port%)+", r=&"+STR$~blk%?3)
23760 ENDPROC
