   10 REM > FBMODEL - the phase 2 editing operations, checked against the model
   20 REM
   30 REM Loaded under the engine, like every driver:
   40 REM   *EXEC FBVDU
   50 REM   *EXEC FBMODEL
   60 REM   RUN
   70 REM
   80 REM No glass and no keyboard. It runs on a 6502 under b-em in a few
   90 REM seconds, which is the point: IL, DL, ICH, DCH, ECH, ED, EL, SU, SD
  100 REM and the scrolling region are index arithmetic, and index arithmetic
  110 REM is exactly the kind of thing that is wrong in the corner cases and
  120 REM right in the middle. Those corners are checked here and never on
  130 REM the hardware, where a wrong answer costs a session rather than a
  140 REM second.
  150 :
  160 cols%=20:rows%=8
  170 cw%=8:ch%=8
  180 md%=21:vdu%=0:pivdu%=2
  190 sim%=TRUE
  200 REM Model only: no framebuffer, no font, no blitter. The editing
  210 REM operations are index arithmetic and pixels would only make the
  220 REM run bigger and slower.
  230 glass%=FALSE
  240 :
  250 DIM buf% 80
  260 REM One buffer, read out with $ string indirection, so each of
  270 REM the three readers below costs ONE string allocation. Built
  280 REM by concatenation they cost twenty, and BBC BASIC never
  290 REM reclaims the blocks a growing string abandons - the model
  300 REM tests ran out of room two thirds of the way through.
  310 tot%=0:bad%=0
  320 ON ERROR PROCerr:END
  330 PROCv_boot
  340 IF vfail$<>"" THEN PRINT "cannot start: ";vfail$:END
  350 PROCtests
  360 PRINT
  370 PRINT tot%-bad%;" of ";tot%;" checks passed"
  380 IF bad%=0 THEN PRINT "[modelok]" ELSE PRINT "[modelbad]"
  390 END
  400 :
10000 DEF PROCtests
10010 PROCt_ich
10020 PROCt_dch
10030 PROCt_ech
10040 PROCt_el
10050 PROCt_ed
10060 PROCt_bce
10070 PROCt_region
10080 PROCt_scroll
10090 PROCt_index
10100 ENDPROC
10110 :
10120 REM ---- character operations, all on one row ----------------------
10130 DEF PROCt_ich
10140 PROCline("abcdefgh")
10150 PROCv_goto(2,0):PROCv_ich(3)
10160 PROCeq("ich","ab...cdefgh.........",FNrow(0))
10170 PROCline("abcdefgh")
10180 PROCv_goto(2,0):PROCv_ich(100)
10190 PROCeq("ich clamped","ab..................",FNrow(0))
10200 ENDPROC
10210 :
10220 DEF PROCt_dch
10230 PROCline("abcdefgh")
10240 PROCv_goto(2,0):PROCv_dch(3)
10250 PROCeq("dch","abfgh...............",FNrow(0))
10260 PROCline("abcdefgh")
10270 PROCv_goto(2,0):PROCv_dch(100)
10280 PROCeq("dch clamped","ab..................",FNrow(0))
10290 ENDPROC
10300 :
10310 REM ECH erases without moving anything, which is the whole difference
10320 REM between it and DCH and the thing a form-filling TUI depends on.
10330 DEF PROCt_ech
10340 PROCline("abcdefgh")
10350 PROCv_goto(2,0):PROCv_ech(3)
10360 PROCeq("ech","ab...fgh............",FNrow(0))
10370 ENDPROC
10380 :
10390 DEF PROCt_el
10400 PROCline("abcdefgh")
10410 PROCv_goto(3,0):PROCv_el(0)
10420 PROCeq("el 0","abc.................",FNrow(0))
10430 PROCline("abcdefgh")
10440 PROCv_goto(3,0):PROCv_el(1)
10450 PROCeq("el 1","....efgh............",FNrow(0))
10460 PROCline("abcdefgh")
10470 PROCv_goto(3,0):PROCv_el(2)
10480 PROCeq("el 2","....................",FNrow(0))
10490 ENDPROC
10500 :
10510 DEF PROCt_ed
10520 PROCv_cls(7,0)
10530 PROCv_text(0,2,"aaa",7,0,0):PROCv_text(0,5,"bbb",7,0,0)
10540 PROCv_goto(1,3):PROCv_ed(0)
10550 PROCeq("ed 0 keeps above","aaa.................",FNrow(2))
10560 PROCeq("ed 0 clears below","....................",FNrow(5))
10570 PROCv_cls(7,0)
10580 PROCv_text(0,2,"aaa",7,0,0):PROCv_text(0,5,"bbb",7,0,0)
10590 PROCv_goto(1,3):PROCv_ed(1)
10600 PROCeq("ed 1 clears above","....................",FNrow(2))
10610 PROCeq("ed 1 keeps below","bbb.................",FNrow(5))
10620 PROCv_cls(7,0)
10630 PROCv_text(0,2,"aaa",7,0,0):PROCv_text(0,5,"bbb",7,0,0)
10640 PROCv_ed(2)
10650 PROCeq("ed 2 row 2","....................",FNrow(2))
10660 PROCeq("ed 2 row 5","....................",FNrow(5))
10670 ENDPROC
10680 :
10690 REM Background colour erase. An erase paints the CURRENT background,
10700 REM not the default one, so clearing inside a coloured panel leaves
10710 REM the colour rather than a black hole. Checked on the exposed row
10720 REM of a scroll too, because that is an erase by another name.
10730 DEF PROCt_bce
10740 PROCv_cls(7,0)
10750 sf%=3:sb%=5
10760 PROCv_goto(0,0):PROCv_el(2)
10770 PROCeq("bce on el","5555555555",FNbg(0,10))
10780 PROCv_cls(7,0)
10790 PROCv_region(0,rows%-1)
10800 PROCv_scroll(0,rows%-1,1,sf%,sb%)
10810 PROCeq("bce on scroll","5555555555",FNbg(rows%-1,10))
10820 sf%=7:sb%=0
10830 ENDPROC
10840 :
10850 REM ---- the scrolling region --------------------------------------
10860 REM Every check below reads column 0 of all eight rows as one string,
10870 REM so an assertion says where the rows ended up rather than how many
10880 REM cells changed.
10890 DEF PROCt_region
10900 PROCdigits:PROCv_region(2,5)
10910 PROCv_goto(0,3):PROCv_il(1)
10920 PROCeq("il inside region","012.3467",FNsig)
10930 PROCdigits:PROCv_region(2,5)
10940 PROCv_goto(0,3):PROCv_dl(1)
10950 PROCeq("dl inside region","01245.67",FNsig)
10960 PROCdigits:PROCv_region(2,5)
10970 PROCv_goto(0,5):PROCv_il(1)
10980 PROCeq("il on the last region row","01234.67",FNsig)
10990 PROCdigits:PROCv_region(2,5)
11000 PROCv_goto(0,0):PROCv_il(1)
11010 PROCeq("il outside region does nothing","01234567",FNsig)
11020 PROCdigits:PROCv_region(2,5)
11030 PROCv_goto(0,7):PROCv_dl(1)
11040 PROCeq("dl outside region does nothing","01234567",FNsig)
11050 ENDPROC
11060 :
11070 REM The full-height scroll is here because of the BBC FOR that always
11080 REM runs its body once. Scrolling a region by its own height is a
11090 REM zero-length move, and an unguarded loop copies one row in from
11100 REM outside the region - a row of somebody else's text appearing in a
11110 REM cleared screen, once, and never reproducibly.
11120 DEF PROCt_scroll
11130 PROCdigits:PROCv_region(0,rows%-1)
11140 PROCv_scroll(0,rows%-1,rows%,7,0)
11150 PROCeq("scroll by the full height","........",FNsig)
11160 PROCdigits
11170 PROCv_sdown(0,rows%-1,rows%,7,0)
11180 PROCeq("scroll down by the full height","........",FNsig)
11190 PROCdigits:PROCv_region(0,rows%-1)
11200 PROCv_su(2)
11210 PROCeq("su 2","234567..",FNsig)
11220 PROCv_sd(2)
11230 PROCeq("sd 2","..234567",FNsig)
11240 ENDPROC
11250 :
11260 REM IND and RI scroll only when the cursor is already against the
11270 REM edge of the region, and leave the cursor where it was when they
11280 REM do. A cursor that moves as well is how a status line creeps.
11290 DEF PROCt_index
11300 PROCdigits:PROCv_region(2,5)
11310 PROCv_goto(0,5):PROCv_ind
11320 PROCeq("ind at the region foot","01345.67",FNsig)
11330 PROCeq("ind left the cursor","5",STR$(cy%))
11340 PROCdigits:PROCv_region(2,5)
11350 PROCv_goto(0,3):PROCv_ind
11360 PROCeq("ind inside the region","01234567",FNsig)
11370 PROCeq("ind moved the cursor","4",STR$(cy%))
11380 PROCdigits:PROCv_region(2,5)
11390 PROCv_goto(0,2):PROCv_ri
11400 PROCeq("ri at the region head","01.23467",FNsig)
11410 PROCeq("ri left the cursor","2",STR$(cy%))
11420 ENDPROC
11430 :
11440 REM ---- fixtures and assertions -----------------------------------
11450 DEF PROCline(s$)
11460 PROCv_cls(7,0)
11470 PROCv_text(0,0,s$,7,0,0)
11480 ENDPROC
11490 :
11500 DEF PROCdigits
11510 LOCAL y%
11520 PROCv_cls(7,0)
11530 FOR y%=0 TO rows%-1:PROCv_put(0,y%,48+y%,7,0,0):NEXT
11540 ENDPROC
11550 :
11560 REM A row as text, with spaces shown as dots so that a trailing
11570 REM difference is visible in the output rather than invisible.
11580 DEF FNrow(y%)
11590 LOCAL i%,c%
11600 FOR i%=0 TO cols%-1
11610   c%=?(scr%+((y%*cols%+i%)*4))
11620   IF c%=32 THEN c%=46
11630   buf%?i%=c%
11640 NEXT
11650 buf%?cols%=13
11660 =$buf%
11670 :
11680 REM Column zero of every row - where a row ended up, in one string.
11690 DEF FNsig
11700 LOCAL y%,c%
11710 FOR y%=0 TO rows%-1
11720   c%=?(scr%+((y%*cols%)*4))
11730   IF c%=32 THEN c%=46
11740   buf%?y%=c%
11750 NEXT
11760 buf%?rows%=13
11770 =$buf%
11780 :
11790 DEF FNbg(y%,n%)
11800 LOCAL i%
11810 FOR i%=0 TO n%-1:buf%?i%=48+?(scr%+((y%*cols%+i%)*4)+3):NEXT
11820 buf%?n%=13
11830 =$buf%
11840 :
11850 DEF PROCeq(n$,w$,g$)
11860 tot%=tot%+1
11870 IF g$=w$ THEN PRINT "pass  ";n$:ENDPROC
11880 bad%=bad%+1
11890 PRINT "FAIL  ";n$
11900 PRINT "      want [";w$;"]"
11910 PRINT "      got  [";g$;"]"
11920 ENDPROC
11930 :
11940 DEF PROCerr
11950 PRINT
11960 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
11970 REPORT:PRINT
11980 PRINT "[modelbad]"
11990 ENDPROC
