   10 REM > FBHW - phase 4. A real captured stream, on the real screen.
   20 REM
   30 REM   CHAIN "FBHW"        on copro 15, *ARMBASIC, tube on
   40 REM
   50 REM Everything before this has tested one half or the other. Phase 3's
   60 REM replays are model only - no framebuffer, no font, no blitter - and
   70 REM the phase 1 self test paints pictures the engine was handed rather
   80 REM than ones it parsed. This is the first time the parser drives the
   90 REM renderer from a stream that came off a real pty.
  100 REM
  110 REM The capture is on the share as CAP, copied there RAW: mirror.sh
  120 REM converts LF to CR, which would rewrite every newline in it.
  130 REM
  140 REM Three things are measured, because they are three different costs
  150 REM and the client will pay them separately:
  160 REM
  170 REM   parse    bytes through PROCv_write with nothing painted
  180 REM   flush    one repaint of everything the parse changed
  190 REM   drained  the two interleaved the way a client actually runs -
  200 REM            take what the socket has, apply it, flush once
  210 REM
  220 REM The model is dumped to RESHW in the same format phase 3 used, so it
  230 REM can be diffed against the emulator's dump of the SAME capture. If
  240 REM those agree cell for cell then the hardware model matches pyte, and
  250 REM the only thing left to judge by eye is the pixels.
  260 :
  270 cols%=80:rows%=64
  280 cw%=8:ch%=8
  290 md%=21:vdu%=1:pivdu%=2
  300 sim%=FALSE
  310 glass%=TRUE
  320 cap$="CAP"
  330 rf$="RESHW"
  340 drain%=512
  350 :
  360 rf%=0:bytes%=0
  370 ON ERROR PROCerr:END
  380 PROCv_boot
  390 IF vfail$<>"" THEN PROCstop(vfail$)
  400 DIM buf% cols%+1
  410 PROCopen
  420 PROCw("[fbhw1]")
  430 PROCw("run="+STR$(TIME))
  440 PROCw("geometry="+STR$(cols%)+"x"+STR$(rows%))
  450 PROCw("screen=&"+STR$~fb%+" pitch="+STR$(pit%))
  460 PROCload
  470 PROCpass1
  480 PROCask("hw_look","Does that look like a real terminal screen? (Y/N)","YN")
  490 PROCask("hw_corrupt","Any torn rows, wrong colours or stray glyphs? (Y/N)","YN")
  500 PROCpass2
  510 REM The dump comes BEFORE the question. PROCask paints the prompt on the
  520 REM bottom row through the engine - deliberately, so what is read is the
  530 REM screen under test - and the first hardware run therefore had the
  540 REM question itself sitting in row 63 of the dump. It was the only row of
  550 REM sixty-four that differed from the emulator.
  560 PROCdump
  570 PROCask("hw_drain","Did it redraw cleanly, without flicker or tearing? (Y/N)","YN")
  580 PROCw("[end]")
  590 PROCshut
  600 VDU 23,1,1:VDU 26:CLS
  610 PRINT "FBHW done - ";rf$;" is on the share."
  620 END
  630 :
  640 REM One bulk load. Read a byte at a time with BGET# and every byte is a
  650 REM Tube round trip and a host filing system call - phase 3 measured
  660 REM 58ms each, which is 20 minutes for a 23K capture.
10000 DEF PROCload
10010 LOCAL f%
10020 f%=OPENIN(cap$)
10030 IF f%=0 THEN PROCstop("cannot open "+cap$)
10040 bytes%=EXT#f%
10050 CLOSE#f%
10060 IF bytes%<1 THEN PROCstop(cap$+" is empty")
10070 DIM cap% bytes%
10080 OSCLI("LOAD "+cap$+" "+STR$~cap%)
10090 PROCw("bytes="+STR$(bytes%))
10100 ENDPROC
10110 :
10120 REM Parse the whole capture with nothing painted, then paint once. This
10130 REM is the upper bound on both halves and the number 2.3a's arithmetic
10140 REM was about.
10150 DEF PROCpass1
10160 LOCAL i%,n%,t
10170 PROCv_writes(CHR$(27)+"c")
10180 T=TIME
10190 FOR i%=0 TO bytes%-1:PROCv_write(cap%?i%):NEXT
10200 t=TIME-T
10210 PROCw("parse_cs="+STR$(t))
10220 IF t>0 THEN PROCw("parse_bytes_per_sec="+STR$(bytes%*100 DIV t))
10230 T=TIME:n%=FNv_flush:t=TIME-T
10240 PROCw("flush_cs="+STR$(t)+" painted="+STR$(n%))
10250 ENDPROC
10260 :
10270 REM The same bytes again, but drained the way a client drains them:
10280 REM apply a chunk, flush once, repeat. 5.5c measured the socket at 3082
10290 REM bytes/sec, so a 512-byte drain is about six a second - and what
10300 REM matters is whether a flush keeps up with one.
10310 DEF PROCpass2
10320 LOCAL i%,j%,n%,f%,p%
10330 PROCv_writes(CHR$(27)+"c")
10340 n%=FNv_flush
10350 f%=0:p%=0
10360 T=TIME
10370 i%=0
10380 REPEAT
10390   FOR j%=i% TO i%+drain%-1
10400     IF j%<bytes% THEN PROCv_write(cap%?j%)
10410   NEXT
10420   p%=p%+FNv_flush
10430   f%=f%+1
10440   i%=i%+drain%
10450 UNTIL i%>=bytes%
10460 PROCw("drain_bytes="+STR$(drain%))
10470 PROCw("drain_flushes="+STR$(f%)+" cs="+STR$(TIME-T)+" painted="+STR$(p%))
10480 IF f%>0 THEN PROCw("drain_cells_per_flush="+STR$(p% DIV f%))
10490 ENDPROC
10500 :
10510 REM Same three sections phase 3 dumps, so tools/vtdiff.py can read it
10520 REM and the hardware model can be diffed against the emulator's.
10530 DEF PROCdump
10540 LOCAL x%,y%
10550 PROCw("[grid]")
10560 FOR y%=0 TO rows%-1:PROCw(FNrow(y%)):NEXT
10570 PROCw("[odd]")
10580 FOR y%=0 TO rows%-1
10590   FOR x%=0 TO cols%-1
10600     IF FNg(x%,y%)<32 OR FNg(x%,y%)>126 THEN PROCw(STR$(y%)+" "+STR$(x%)+" "+STR$(FNg(x%,y%)))
10610   NEXT
10620 NEXT
10630 PROCw("[runs]")
10640 FOR y%=0 TO rows%-1:PROCruns(y%):NEXT
10650 ENDPROC
10660 :
10670 DEF PROCruns(y%)
10680 LOCAL x%,s%,f%,b%,l%
10690 s%=0:f%=FNf(0,y%):b%=FNb(0,y%):l%=FNl(0,y%)
10700 FOR x%=1 TO cols%-1
10710   IF FNf(x%,y%)<>f% OR FNb(x%,y%)<>b% OR FNl(x%,y%)<>l% THEN PROCw(STR$(y%)+" "+STR$(s%)+" "+STR$(x%-s%)+" "+STR$(f%)+" "+STR$(b%)+" "+STR$(l%)):s%=x%:f%=FNf(x%,y%):b%=FNb(x%,y%):l%=FNl(x%,y%)
10720 NEXT
10730 PROCw(STR$(y%)+" "+STR$(s%)+" "+STR$(cols%-s%)+" "+STR$(f%)+" "+STR$(b%)+" "+STR$(l%))
10740 ENDPROC
10750 :
10760 DEF FNrow(y%)
10770 LOCAL i%,c%
10780 FOR i%=0 TO cols%-1
10790   c%=FNg(i%,y%)
10800   IF c%<32 OR c%>126 THEN c%=126
10810   buf%?i%=c%
10820 NEXT
10830 buf%?cols%=13
10840 =$buf%
10850 :
10860 DEF FNg(x%,y%)
10870 =?(scr%+((y%*cols%+x%)*4))+(?(scr%+((y%*cols%+x%)*4)+1) AND 15)*256
10880 :
10890 DEF FNf(x%,y%)
10900 =?(scr%+((y%*cols%+x%)*4)+2)
10910 :
10920 DEF FNb(x%,y%)
10930 =?(scr%+((y%*cols%+x%)*4)+3)
10940 :
10950 DEF FNl(x%,y%)
10960 =?(scr%+((y%*cols%+x%)*4)+1) DIV 16
10970 :
10980 REM The question goes on the bottom row THROUGH THE ENGINE, over the
10990 REM capture, so what is being read is the screen under test. A wrong
11000 REM key says so rather than doing nothing.
11010 DEF PROCask(k$,p$,v$)
11020 REM Nobody presses a key under b-em, and GET would hang until the
11030 REM harness timed the run out.
11040 IF sim% THEN ENDPROC
11050 LOCAL k%,c$,n%,m$
11060 m$=""
11070 REPEAT
11080   PROCv_text(0,rows%-1,STRING$(cols%," "),15,4,0)
11090   PROCv_text(0,rows%-1,p$+m$,15,4,0)
11100   n%=FNv_flush
11110   k%=GET
11120   IF k%>96 AND k%<123 THEN k%=k%-32
11130   c$=CHR$(k%)
11140   m$="  <- Y or N"
11150 UNTIL INSTR(v$,c$)>0
11160 PROCw(k$+"="+c$)
11170 ENDPROC
11180 :
11190 DEF PROCopen
11200 rf%=OPENOUT(rf$)
11210 ENDPROC
11220 :
11230 DEF PROCw(s$)
11240 LOCAL i%
11250 IF rf%=0 THEN ENDPROC
11260 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
11270 BPUT#rf%,13:BPUT#rf%,10
11280 ENDPROC
11290 :
11300 DEF PROCshut
11310 IF rf%<>0 THEN CLOSE#rf%
11320 rf%=0
11330 ENDPROC
11340 :
11350 DEF PROCstop(s$)
11360 PROCw("fail="+s$)
11370 PROCw("[end]")
11380 PROCshut
11390 VDU 23,1,1:VDU 26:CLS
11400 PRINT "FBHW cannot start: ";s$
11410 END
11420 :
11430 DEF PROCerr
11440 VDU 26,23,1,1
11450 PROCw("error="+STR$(ERR)+" line="+STR$(ERL)+" stage="+STR$(stage%))
11460 PROCw("[end]")
11470 PROCshut
11480 CLS
11490 PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
11500 REPORT:PRINT
11510 ENDPROC