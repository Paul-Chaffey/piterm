   10 REM > FBBLIT - the blitter's arithmetic, checked without hardware
   20 REM
   30 REM FBVDU's inner loop is PROCxp and PROCblit (docs/fbvdu.md 4.4).
   40 REM Neither needs a framebuffer: they need an address, a pitch and
   50 REM somewhere to write. So point them at a DIMmed block and the
   60 REM whole thing runs on a 6502 Master, under the emulator, in
   70 REM seconds - which is the edit-test loop 2.3a said was worth
   80 REM protecting, applied to the one piece of FBVDU that can have it.
   90 REM
  100 REM The procedures below are COPIED VERBATIM from fbfont.bas. If
  110 REM they are changed there, change them here - a test of a
  120 REM different copy tests nothing.
  130 REM
  140 REM It self-checks rather than asking to be eyeballed: every pixel
  150 REM written is compared against the font bit it came from, and the
  160 REM bytes around each cell are sentinels, so a blit that runs off
  170 REM the end of a row is caught rather than admired.
  180 REM
  190 REM What it CANNOT tell you: whether the real framebuffer agrees
  200 REM about byte order. Both the 6502 and the ARM store the low byte
  210 REM of a word at the lowest address, so the logic transfers, but
  220 REM the hardware answer comes from fbfont.bas on copro 15.
  230 REM
  240 REM BASIC IV SAFE - no SYS, no MODE 21, runs on the host.
  250 :
  260 cw%=8:ch%=8:pit%=16:hi%=16
  270 bad%=0:err%=0
  280 :
  290 DIM fb% pit%*hi%-1,font% 256*8,xp% 63
  300 :
  310 PRINT "FBBLIT - blitter arithmetic on a fake screen"
  320 PRINT STRING$(46,"-")
  330 PRINT "screen ";pit%;" x ";hi%;" bytes, cells ";cw%;" x ";ch%
  340 PRINT
  350 PROCfont
  360 :
  370 REM Two asymmetric glyphs. A mirrored blit is the failure this is
  380 REM most likely to catch, and a symmetric letter would hide it.
  390 PROCwipe
  400 PROCxp(1,0)
  410 PROCblit(0,0,70)
  420 PROCart(0,0)
  430 PROCcheck(0,0,70,1,0)
  440 :
  450 PROCblit(1,1,76)
  460 PROCart(1,1)
  470 PROCcheck(1,1,76,1,0)
  480 :
  490 REM A colour change is 16 word writes and nothing per cell, so the
  500 REM same glyph in different inks must come out identically shaped.
  510 PROCxp(6,3)
  520 PROCblit(1,0,70)
  530 PROCcheck(1,0,70,6,3)
  540 :
  550 PROCguard
  560 :
  570 PRINT STRING$(46,"-")
  580 IF err%=0 AND bad%=0 THEN PRINT "PASS - ";: ELSE PRINT "FAIL - ";
  590 PRINT err%;" wrong pixels, ";bad%;" sentinels overwritten"
  600 IF err%>0 THEN PRINT "Mirrored art means PROCxp fills the word backwards."
  610 IF bad%>0 THEN PRINT "A blit wrote outside its cell - check the pitch maths."
  620 END
  630 :
  640 REM ---- the font -------------------------------------------------
  650 REM F and L, drawn by hand. Bit 7 is the leftmost pixel, which is
  660 REM the order fbfont.bas harvests into.
  670 DEF PROCfont
  680 LOCAL i%,c%,b%
  690 FOR i%=0 TO 256*8-1:font%?i%=0:NEXT
  700 RESTORE
  710 FOR c%=1 TO 2
  720   READ b%
  730   FOR i%=0 TO 7:READ font%?(b%*8+i%):NEXT
  740 NEXT
  750 ENDPROC
  760 :
  770 DATA 70, &FE,&C0,&C0,&FC,&C0,&C0,&C0,&00
  780 DATA 76, &C0,&C0,&C0,&C0,&C0,&C0,&FE,&00
  790 :
  800 REM ---- checking -------------------------------------------------
  810 REM Every byte of the fake screen starts at 255, a value no test
  820 REM here writes, so anything still 255 was never touched and
  830 REM anything else outside a blitted cell should not have been.
  840 DEF PROCwipe
  850 LOCAL i%
  860 FOR i%=0 TO pit%*hi%-1:fb%?i%=255:NEXT
  870 ENDPROC
  880 :
  890 DEF PROCcheck(x%,y%,g%,f%,b%)
  900 LOCAL r%,i%,a%,m%,v%,w%
  910 FOR r%=0 TO ch%-1
  920   a%=fb%+(y%*ch%+r%)*pit%+x%*cw%
  930   m%=128
  940   FOR i%=0 TO cw%-1
  950     IF (font%?(g%*ch%+r%) AND m%)<>0 THEN v%=f% ELSE v%=b%
  960     w%=a%?i%
  970     IF w%<>v% THEN err%=err%+1
  980     m%=m% DIV 2
  990   NEXT
 1000 NEXT
 1010 ENDPROC
 1020 :
 1030 REM Cell (0,1) is never written by any blit above, so all 64 of its
 1040 REM bytes must still be sentinel. A row-pitch error lands here.
 1050 DEF PROCguard
 1060 LOCAL r%,i%,a%
 1070 FOR r%=0 TO ch%-1
 1080   a%=fb%+(ch%+r%)*pit%
 1090   FOR i%=0 TO cw%-1
 1100     IF a%?i%<>255 THEN bad%=bad%+1
 1110   NEXT
 1120 NEXT
 1130 ENDPROC
 1140 :
 1150 DEF PROCart(x%,y%)
 1160 LOCAL r%,i%,a%,v%,s$
 1170 PRINT "cell ";x%;",";y%;":"
 1180 FOR r%=0 TO ch%-1
 1190   a%=fb%+(y%*ch%+r%)*pit%+x%*cw%
 1200   s$=""
 1210   FOR i%=0 TO cw%-1
 1220     v%=a%?i%
 1230     IF v%=255 THEN s$=s$+"?" ELSE IF v%=0 OR v%=3 THEN s$=s$+"." ELSE s$=s$+"#"
 1240   NEXT
 1250   PRINT "   ";s$
 1260 NEXT
 1270 PRINT
 1280 ENDPROC
 1290 :
 1300 REM ---- the code under test, verbatim from fbfont.bas ------------
 1310 DEF PROCxp(f%,b%)
 1320 LOCAL n%,i%,m%,a%
 1330 FOR n%=0 TO 15
 1340   a%=xp%+n%*4:m%=8
 1350   FOR i%=0 TO 3
 1360     IF (n% AND m%)<>0 THEN a%?i%=f% ELSE a%?i%=b%
 1370     m%=m% DIV 2
 1380   NEXT
 1390 NEXT
 1400 ENDPROC
 1410 :
 1420 DEF PROCblit(x%,y%,g%)
 1430 LOCAL a%,f%,i%,b%
 1440 a%=fb%+y%*ch%*pit%+x%*cw%
 1450 f%=font%+g%*ch%
 1460 FOR i%=0 TO ch%-1
 1470   b%=f%?i%
 1480   !a%=xp%!((b% DIV 16)*4)
 1490   a%!4=xp%!((b% AND 15)*4)
 1500   a%=a%+pit%
 1510 NEXT
 1520 ENDPROC
