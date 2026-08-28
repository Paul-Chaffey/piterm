   10 REM > PALETTE2 - reaching all 256 shades: colour AND tint
   20 REM
   30 REM PALETTE swept GCOL 0,n for n=0-255 and the top of the range came
   40 REM out near-white. That is not saturation. A RISC OS 8bpp mode is 64
   50 REM colours x 4 tints: GCOL carries the colour, and the tint is a
   60 REM SEPARATE selector - VDU 23,17,r,t| with r=2 for graphics
   70 REM foreground and t = 0, 64, 128 or 192. Tint adds equal R+G+B, so
   80 REM driving both from one number fades the top quarter to white.
   90 REM
  100 REM This probe answers three things with numbers, not by eye:
  110 REM   1. do 64 colours x 4 tints give 256 DISTINCT values
  120 REM   2. how many distinct values the old GCOL 0,n sweep really gave
  130 REM   3. whether VDU 19 can reprogram anything in this mode
  140 REM
  150 REM POINT(x,y) reads back the logical colour actually plotted, which
  160 REM turns "they look the same" into a count. If POINT is unsupported
  170 REM it returns -1 and the counts are reported as unavailable.
  180 REM
  190 REM BASIC IV safe - no CASE, WHILE, REPORT$, RECTANGLE FILL, TINT.
  200 :
  210 md%=21
  220 :
  230 DIM v%(255)
  240 n1%=0:n2%=0:pt%=TRUE:T=0:E=0
  250 ON ERROR PROCerr:END
  260 :
  270 MODE md%
  280 PROCtinted
  290 PROCpause
  300 PROCflat
  310 PROCpause
  320 PROCvdu19
  330 PRINT
  340 PRINT "PALETTE2 done - record against specification.md 2.3 and 7 Q7"
  350 END
  360 :
  370 REM ---- page 1: the correct way - 64 colours x 4 tints --------------
  380 :
  390 DEF PROCtinted
  400 LOCAL c%,t%,i%,x%,y%
  410 CLS
  420 PRINT "64 GCOL colours x 4 tints - tint 0 top, 192 bottom"
  430 i%=0
  440 FOR t%=0 TO 3
  450   PROCtint(t%*64)
  460   y%=760-t%*180
  470   FOR c%=0 TO 63
  480     x%=c%*20
  490     PROCbox(x%,y%,19,170,c%)
  500     v%(i%)=FNread(x%+8,y%+80)
  510     i%=i%+1
  520   NEXT
  530 NEXT
  540 PROCtint(0)
  550 n1%=FNdistinct
  560 COLOUR 63
  570 VDU 31,0,1
  580 IF pt% THEN PRINT "distinct values read back: ";n1%;" of 256"; ELSE PRINT "POINT unsupported - judge by eye";
  590 ENDPROC
  600 :
  610 REM ---- page 2: what PALETTE actually did ---------------------------
  620 :
  630 DEF PROCflat
  640 LOCAL c%,x%,y%
  650 CLS
  660 PRINT "the old sweep: GCOL 0,n for n=0-255, tint left at 0"
  670 FOR c%=0 TO 255
  680   x%=(c% MOD 16)*80
  690   y%=(15-(c% DIV 16))*60
  700   PROCbox(x%,y%,78,58,c%)
  710   v%(c%)=FNread(x%+8,y%+20)
  720 NEXT
  730 n2%=FNdistinct
  740 COLOUR 63
  750 VDU 31,0,1
  760 IF pt% THEN PRINT "distinct values read back: ";n2%;" of 256";
  770 ENDPROC
  780 :
  790 REM ---- page 3: is the palette programmable at all -------------------
  800 :
  810 REM The PRM says VDU 19 in an 8bpp mode reaches only the low four
  820 REM bits' palette entries - the high bits come straight from the
  830 REM pixel value. If that holds, the top strip changes and the bottom
  840 REM one does not, and an arbitrary 256-entry palette is impossible.
  850 DEF PROCvdu19
  860 LOCAL c%,l%
  870 CLS
  880 PRINT "VDU 19 probe - same 64 colours before and after"
  890 FOR c%=0 TO 63
  900   PROCbox(c%*20,600,19,200,c%)
  910 NEXT
  920 FOR l%=0 TO 15
  930   VDU 19,l%,16,l%*17,0,255-l%*17
  940 NEXT
  950 FOR c%=0 TO 63
  960   PROCbox(c%*20,300,19,200,c%)
  970 NEXT
  980 COLOUR 63
  990 VDU 31,0,2
 1000 PRINT "top: default palette   bottom: after VDU 19,l,16,r,0,b";
 1010 VDU 31,0,3
 1020 PRINT "identical = palette not programmable here";
 1030 ENDPROC
 1040 :
 1050 REM ---- helpers -----------------------------------------------------
 1060 :
 1070 REM VDU 23 always takes nine parameters after the 23.
 1080 DEF PROCtint(tv%)
 1090 VDU 23,17,2,tv%,0,0,0,0,0,0
 1100 ENDPROC
 1110 :
 1120 DEF FNread(rx%,ry%)
 1130 LOCAL r%
 1140 r%=POINT(rx%,ry%)
 1150 IF r%<0 THEN pt%=FALSE
 1160 =r%
 1170 :
 1180 DEF FNdistinct
 1190 LOCAL i%,j%,d%,seen%
 1200 IF pt%=FALSE THEN =0
 1210 d%=0
 1220 FOR i%=0 TO 255
 1230   seen%=FALSE
 1240   FOR j%=0 TO i%-1
 1250     IF v%(j%)=v%(i%) THEN seen%=TRUE
 1260   NEXT
 1270   IF seen%=FALSE THEN d%=d%+1
 1280 NEXT
 1290 =d%
 1300 :
 1310 DEF PROCbox(bx%,by%,bw%,bh%,bc%)
 1320 GCOL 0,bc%
 1330 MOVE bx%,by%
 1340 MOVE bx%+bw%,by%
 1350 PLOT 85,bx%,by%+bh%
 1360 PLOT 85,bx%+bw%,by%+bh%
 1370 ENDPROC
 1380 :
 1390 DEF PROCpause
 1400 LOCAL k%
 1410 COLOUR 63
 1420 VDU 31,0,0
 1430 PRINT "SPACE for next";
 1440 k%=GET
 1450 ENDPROC
 1460 :
 1470 DEF PROCerr
 1480 PRINT
 1490 PRINT "Error ";ERR;" at line ";ERL
 1500 REPORT:PRINT
 1510 IF ERR=25 THEN PRINT "MODE ";md%;" refused - try MODE 64 (640x512 8bpp)"
 1520 ENDPROC
