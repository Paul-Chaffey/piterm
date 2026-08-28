   10 REM > PALETTE - what 256 colours on a BBC Master actually look like
   20 REM
   30 REM REVISED 2026-08-19. This originally swept GCOL 0,n for n=0-255,
   31 REM which is not how a 256-colour mode works: it is 64 colours x 4
   32 REM tints, and GCOL above 63 washes out to near-white (2.3). Every
   33 REM index below is now split - colour in the low 6 bits, tint in the
   34 REM next 2 - so all three pages show the real 256-shade space.
   35 REM palette2.bas is the probe that established this; this one is for
   36 REM looking at the result.
   37 REM
   40 REM Three pages, SPACE between them:
   45 REM   1. all 256 shades as a labelled 16x16 grid
   50 REM   2. the same 256 as a continuous ramp - reveals whether the
   60 REM      palette is a smooth ordering or an RGB-cube ordering
   70 REM   3. a two-axis blend, and a plot-rate figure
   80 REM
   90 REM Why it matters: 2.3 assumed 256 colours was a full match for
  100 REM xterm-256color. It is not - the 16 ANSI colours can be set exactly
  110 REM with VDU 19, the other 240 need a nearest match into this space.
  120 REM
  130 REM MODE 21 is 640x512 in 1280x1024 graphics units.
  140 :
  150 md%=21
  160 :
  170 p%=0:T=0:E=0
  180 ON ERROR PROCerr:END
  190 :
  200 MODE md%
  210 PROCgrid
  220 PROCpause
  230 PROCramp
  240 PROCpause
  250 PROCblend
  260 PRINT
  270 PRINT "PALETTE done"
  280 END
  290 :
  300 REM ---- page 1: the whole palette, addressable by number ------------
  310 :
  320 DEF PROCgrid
  330 LOCAL c%,x%,y%
  340 CLS
  350 PRINT "PALETTE - all 256 shades, colour + tint"
  360 FOR c%=0 TO 255
  370   x%=(c% MOD 16)*80
  380   y%=(15-(c% DIV 16))*60
  390   PROCbox(x%,y%,78,58,c%)
  400 NEXT
  410 GCOL 0,7
  420 VDU 31,0,1
  430 PRINT "0-15 top row, 240-255 bottom";
  440 ENDPROC
  450 :
  460 REM ---- page 2: 256 strips, no gaps ---------------------------------
  470 :
  480 REM A smooth left-to-right fade means the numbering is perceptual.
  490 REM Repeating bands mean it is an RGB cube, and a terminal will need
  500 REM a lookup table to map xterm indices onto it.
  510 DEF PROCramp
  520 LOCAL c%
  530 CLS
  540 PRINT "256 colours in numeric order - look for structure"
  550 FOR c%=0 TO 255
  560   PROCbox(c%*5,200,5,700,c%)
  570 NEXT
  580 GCOL 0,7
  590 VDU 31,0,1
  600 PRINT "smooth fade = perceptual order, bands = RGB cube";
  610 ENDPROC
  620 :
  630 REM ---- page 3: blend, and how fast we can fill ----------------------
  640 :
  650 DEF PROCblend
  660 LOCAL x%,y%,c%,n%
  670 CLS
  680 PRINT "two-axis blend"
  690 n%=0
  700 T=TIME
  710 FOR y%=0 TO 15
  720   FOR x%=0 TO 31
  730     c%=(x%*8+y%*16) MOD 256
  740     PROCbox(x%*40,y%*56,40,56,c%)
  750     n%=n%+1
  760   NEXT
  770 NEXT
  780 E=TIME-T
  790 GCOL 0,7
  800 VDU 31,0,1
  810 IF E>0 THEN PRINT n%;" filled rects in ";E;" cs = ";(n%*100) DIV E;"/sec";
  820 ENDPROC
  830 :
  840 REM ---- two triangles, because RECTANGLE FILL is BASIC V ------------
  850 :
  855 REM bc% is a 0-255 shade index: low 6 bits colour, next 2 tint.
  860 DEF PROCbox(bx%,by%,bw%,bh%,bc%)
  865 VDU 23,17,2,((bc% DIV 64) MOD 4)*64,0,0,0,0,0,0
  870 GCOL 0,bc% MOD 64
  880 MOVE bx%,by%
  890 MOVE bx%+bw%,by%
  900 PLOT 85,bx%,by%+bh%
  910 PLOT 85,bx%+bw%,by%+bh%
  920 ENDPROC
  930 :
  940 DEF PROCpause
  950 LOCAL k%
  960 GCOL 0,7
  970 VDU 31,0,0
  980 PRINT "SPACE for next";
  990 k%=GET
 1000 ENDPROC
 1010 :
 1020 DEF PROCerr
 1030 PRINT
 1040 PRINT "Error ";ERR;" at line ";ERL
 1050 REPORT:PRINT
 1060 IF ERR=25 THEN PRINT "MODE ";md%;" refused - try MODE 64 (640x512 8bpp)"
 1070 ENDPROC
