   10 REM > FBTEST - can we reach the Pi framebuffer from BASIC?
   20 REM
   30 REM specification.md 2.3a established from PiTubeDirect source
   40 REM that VDU variable 148 (&94, V_SCREENSTART) returns the real
   50 REM framebuffer address, and that copro 15 runs bare metal ON
   60 REM the Pi - so that address should be directly writable. This
   70 REM turns "the source says so" into something on the screen.
   80 REM
   90 REM Three questions, in order, each meaningless if the one
  100 REM before it failed:
  110 REM   1. does SYS reach OS_ReadVduVariables from BASIC at all
  120 REM   2. is the address plausible, with a sane size and pitch
  130 REM   3. does a poked byte become a visible pixel
  140 REM
  150 REM ARM NATIVE ONLY - copro 15, reached with *ARMBASIC. SYS and
  160 REM the 32-bit addresses do not exist on the 6502 co-pros.
  170 :
  180 md%=21
  190 :
  200 DIM q% 63,r% 63
  210 fb%=0:sz%=0:pit%=0:wid%=0:hei%=0:bpp%=0
  220 ON ERROR PROCerr:END
  230 :
  240 MODE md%
  250 PRINT "FBTEST - mode ";md%
  260 PRINT STRING$(46,"-")
  270 PROCvars
  280 PROCreport
  290 IF fb%=0 THEN PRINT "no framebuffer address - stopping":END
  300 PROCpause
  310 PROCpixels
  320 PRINT
  330 PRINT "FBTEST done - record against specification.md 2.3a"
  340 END
  350 :
  360 REM ---- 1 and 2: ask the VDU driver where the screen is --------------
  370 :
  380 REM OS_ReadVduVariables takes a -1 terminated list of variable
  390 REM numbers at R0 and writes the values to R1. 148 SCREENSTART,
  400 REM 150 TOTALSCREENSIZE, 4/5 window width/height in characters,
  410 REM 6 line length in bytes, 9 bits per pixel (log2).
  420 DEF PROCvars
  430 !q%=148:q%!4=150:q%!8=6:q%!12=4:q%!16=5:q%!20=9:q%!24=-1
  440 SYS "OS_ReadVduVariables",q%,r%
  450 fb%=!r%:sz%=r%!4:pit%=r%!8:wid%=r%!12:hei%=r%!16:bpp%=r%!20
  460 ENDPROC
  470 :
  480 DEF PROCreport
  490 PRINT "screen start   &";~fb%
  500 PRINT "screen size    ";sz%;" bytes"
  510 PRINT "bytes per line ";pit%
  520 PRINT "text window    ";wid%+1;" x ";hei%+1;" characters"
  530 PRINT "bits per pixel ";2^bpp%
  540 PRINT
  550 IF pit%>0 THEN PRINT "implied height ";sz% DIV pit%;" pixel rows"
  560 PRINT
  570 PRINT "A plausible address with size = pitch x height means the"
  580 PRINT "driver is telling the truth and step 3 is worth trying."
  590 ENDPROC
  600 :
  610 REM ---- 3: is it really the screen ----------------------------------
  620 :
  630 REM Draw a marker no VDU call could have produced: a solid block
  640 REM in the top-left, then a diagonal, poking bytes directly. In
  650 REM an 8bpp mode one byte is one pixel and the value is the
  660 REM colour number, so this also shows the palette is ours.
  670 DEF PROCpixels
  680 LOCAL x%,y%,a%
  690 CLS
  700 PRINT "poking pixels directly - no VDU calls below this line"
  710 T=TIME
  720 FOR y%=0 TO 63
  730   a%=fb%+y%*pit%
  740   FOR x%=0 TO 63
  750     a%?x%=(x%+y%) AND 63
  760   NEXT
  770 NEXT
  780 FOR y%=0 TO 199
  785   a%=fb%+y%*pit%
  790   a%?(y%+80)=63
  800 NEXT
  810 E=TIME-T
  820 VDU 31,0,30
  830 PRINT "64x64 block and a 200-pixel diagonal, ";E;" cs"
  840 PRINT
  850 PRINT "If they are on screen, the framebuffer is ours and a"
  860 PRINT "terminal can own the cell grid - 2.3a, 8 Step 3."
  870 PRINT "If the machine hung or nothing appeared, it is not."
  880 ENDPROC
  890 :
  900 DEF PROCpause
  910 LOCAL k%
  920 PRINT "SPACE to poke pixels";
  930 k%=GET
  940 ENDPROC
  950 :
  960 DEF PROCerr
  970 PRINT
  980 PRINT "Error ";ERR;" at line ";ERL
  990 REPORT:PRINT
 1000 IF ERR=25 THEN PRINT "MODE ";md%;" refused - is *PIVDU set?"
 1010 PRINT "Error 24 or similar at the SYS means the SWI is absent."
 1020 ENDPROC
