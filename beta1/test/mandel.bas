   10 REM > MANDEL - Mandelbrot set, co-processor showcase
   20 REM
   30 REM Deliberately CPU-bound: floating point in interpreted BASIC
   40 REM with no OS calls in the inner loop. On a 2MHz BBC this takes
   50 REM many minutes; on the Pi co-processor it should be dramatic.
   60 REM
   70 REM Also exercises the Pi VDU driver - set md% to 21 for the
   80 REM extended 640x512 256-colour mode (specification.md 2.3),
   90 REM or 1 / 2 for a normal BBC screen.
  100 :
  110 md%=21
  111 REM fill%=TRUE fills each computed cell, which is what you want to
  112 REM look at: cells are xs% units apart, 4 pixels in mode 21, so a
  113 REM single PLOT 69 per cell draws a dotted picture, not a solid one.
  114 fill%=TRUE
  115 REM Iterations doubles as the colour index, so in a 256-colour
  116 REM mode we want 255 of them - anything less leaves most of the
  117 REM palette unused. Set md%=1:mx%=20 to compare against the host
  118 REM (no Tube); the two only compare if mx%/w%/h% match.
  119 REM
  120 mx%=20
  125 IF md%=21 OR md%=64 THEN mx%=255
  126 REM Timings compare across runs only at the same fill% - filling a
  127 REM cell is four graphics calls where a point is one.
  128 REM 2026-08-19: the 256 shades are 64 colours x 4 TINTS, not 256
  129 REM GCOL numbers (2.3). GCOL 0,n above 63 washes out to near-white,
  130 REM so the old "GCOL 0,i% MOD 256" painted most of the set white.
  131 REM The count is split: colour low 6 bits, tint next 2.
  135 :
  140 MODE md%
  150 PRINT "MANDEL - mode ";md%;", ";mx%;" iterations";
  155 IF fill% THEN PRINT ", filled" ELSE PRINT ", points"
  160 T=TIME
  170 :
  180 sx%=0:sy%=0
  190 PROCsize
  200 FOR py%=0 TO h%-1
  210   ci=(py%-h%/2)*3.0/h%
  220   FOR px%=0 TO w%-1
  230     cr=(px%-w%/2)*3.5/w%-0.5
  240     zr=0:zi=0:i%=0
  250     REPEAT
  260       t=zr*zr-zi*zi+cr
  270       zi=2*zr*zi+ci
  280       zr=t
  290       i%=i%+1
  300     UNTIL i%>=mx% OR (zr*zr+zi*zi)>4
  310     IF i%<mx% THEN PROCink(i%):PROCcell(px%*xs%,py%*ys%)
  320   NEXT
  330 NEXT
  340 :
  350 E=TIME-T
  360 VDU 5
  370 MOVE 0,60
  380 PRINT "done in ";E DIV 100;".";(E MOD 100) DIV 10;"s";
  390 VDU 4
  400 PRINT
  410 PRINT "elapsed ";E;" centiseconds"
  420 END
  430 :
  440 REM Pick a plot grid and colour count for the current mode.
  450 REM 320x256 through xs%/ys% gives 2x2-pixel cells in mode 21. Drop
  460 REM to 160x128 for chunky 4x4 blocks at a quarter of the compute,
  465 REM or raise to 640x512 for one cell per pixel at four times it.
  470 DEF PROCsize
  480 w%=320:h%=256
  490 xs%=1280 DIV w%:ys%=1024 DIV h%
  500 nc%=16:nt%=1
  510 IF md%=1 THEN nc%=4
  520 IF md%=2 THEN nc%=16
  525 IF md%=21 OR md%=64 THEN nc%=64:nt%=4
  530 IF md%=0 OR md%=4 THEN nc%=2
  535 lt%=-1
  540 ENDPROC
  550 :
  560 REM Colour AND tint from one index. The tint is a mode setting, not
  570 REM part of the GCOL number, so it is only re-issued when it changes
  580 REM - a VDU 23 on every pixel would be measuring the wrong thing in
  590 REM a benchmark. nt%=1 outside 256-colour modes makes t% always 0.
  600 DEF PROCink(n%)
  610 LOCAL t%
  620 t%=((n% DIV nc%) MOD nt%)*64
  630 IF t%<>lt% THEN VDU 23,17,2,t%,0,0,0,0,0,0:lt%=t%
  640 GCOL 0,n% MOD nc%
  650 ENDPROC
  660 :
  670 REM One computed cell. Two triangles rather than RECTANGLE FILL,
  680 REM which is BASIC V only (9.4) - this has to run on the 6502
  690 REM co-processors too. xs%-1 / ys%-1 so cells butt up without
  700 REM overlapping the next one along.
  710 DEF PROCcell(cx%,cy%)
  720 IF fill%=FALSE THEN PLOT 69,cx%,cy%:ENDPROC
  730 MOVE cx%,cy%
  740 MOVE cx%+xs%-1,cy%
  750 PLOT 85,cx%,cy%+ys%-1
  760 PLOT 85,cx%+xs%-1,cy%+ys%-1
  770 ENDPROC
