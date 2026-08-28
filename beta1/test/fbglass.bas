   10 REM > FBGLASS - does the GLASS still agree with the model after a real
   20 REM stream, with the cursor on?
   30 REM
   40 REM Phase 5. A live session showed text fragments in the wrong places,
   50 REM and the same bytes replayed through the engine matched pyte cell for
   60 REM cell - so the MODEL is right and the PIXELS are wrong. That can only
   70 REM be the flush or the shadow, and the cursor is the one thing that
   80 REM writes to the glass without telling the shadow about it.
   90 REM
  100 REM Every replay so far has run with cvis%=FALSE. This one runs with the
  110 REM cursor on, drains in chunks the way a client does, and then asks the
  120 REM only question that matters: if every cell were repainted from
  130 REM scratch, would the glass change? If it would, the flush has been
  140 REM skipping cells it should have painted, and that is exactly what a
  150 REM stale fragment on a real screen is.
  160 :
  170 cols%=80:rows%=64
  180 cw%=8:ch%=8
  190 md%=21:vdu%=0:pivdu%=2
  200 sim%=TRUE
  210 glass%=TRUE
  220 cap$="CAP"
  230 drain%=512
  240 :
  250 ON ERROR PROCerr:END
  260 PROCv_boot
  270 IF vfail$<>"" THEN PRINT "cannot start: ";vfail$:END
  280 PROCload
  290 PROCreplay
  300 PROCverify
  310 PRINT "[glassdone]"
  320 END
  330 :
10000 DEF PROCload
10010 LOCAL f%
10020 f%=OPENIN(cap$)
10030 IF f%=0 THEN PRINT "cannot open ";cap$:END
10040 bytes%=EXT#f%
10050 CLOSE#f%
10060 DIM cap% bytes%
10070 OSCLI("LOAD "+cap$+" "+STR$~cap%)
10080 DIM copy% rows%*ch%*pit%
10090 PRINT "loaded ";bytes%;" bytes"
10100 ENDPROC
10110 :
10120 REM Drained in chunks with the cursor visible, which is what PTERM does
10130 REM and what no earlier replay did.
10140 DEF PROCreplay
10150 LOCAL i%,j%,n%,f%
10160 cvis%=TRUE
10170 f%=0:i%=0
10180 REPEAT
10190   FOR j%=i% TO i%+drain%-1
10200     IF j%<bytes% THEN PROCv_write(cap%?j%)
10210   NEXT
10220   n%=FNv_flush
10230   f%=f%+1
10240   i%=i%+drain%
10250 UNTIL i%>=bytes%
10260 PRINT "drained in ";f%;" flushes"
10270 ENDPROC
10280 :
10290 REM Keep the glass, force every cell to be repainted, and see whether
10300 REM the pixels changed. A cell that changes is one the flush thought was
10310 REM already correct and was not.
10320 DEF PROCverify
10330 LOCAL i%,n%,bad%,row%
10340 REM Take the cursor down FIRST, through the flush, so the comparison is
10350 REM between two screens that both have no cursor on them. Forcing
10360 REM con%=FALSE instead just prevents the erase, and the cursor still
10370 REM sitting there then reads as one stale cell - which is a fault in
10380 REM this test, not in the engine.
10390 cvis%=FALSE
10400 n%=FNv_flush
10410 FOR i%=0 TO rows%*ch%*pit%-4 STEP 4:copy%!i%=fb%!i%:NEXT
10420 FOR i%=0 TO cols%*rows%-1:shd%!(i%*4)=NOT scr%!(i%*4):NEXT
10430 n%=FNv_flush
10440 bad%=0:row%=-1
10450 FOR i%=0 TO rows%*ch%*pit%-4 STEP 4
10460   IF fb%!i%<>copy%!i% THEN bad%=bad%+1:IF row%<0 THEN row%=i% DIV pit% DIV ch%
10470 NEXT
10480 PRINT "repainted ";n%;" cells"
10490 PRINT "glass words that changed: ";bad%
10500 IF bad%=0 THEN PRINT "[glassok]" ELSE PRINT "[glassstale] first bad row ";row%
10510 ENDPROC
10520 :
10530 DEF PROCerr
10540 PRINT:PRINT "Error ";ERR;" at line ";ERL;" stage ";stage%
10550 REPORT:PRINT
10560 PRINT "[glassdone]"
10570 ENDPROC