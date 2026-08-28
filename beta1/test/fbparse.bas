   10 REM > FBPARSE - the phase 2b VT parser, checked against the model
   20 REM
   30 REM   *EXEC FBVDU
   40 REM   *EXEC FBPARSE
   50 REM   RUN
   60 REM
   70 REM Model only, so it runs on a co-processor under b-em in seconds and
   80 REM every answer is a fact about the cell model rather than about a
   90 REM photograph of a monitor. Bytes go in through PROCv_write, exactly
  100 REM as they will arrive from the socket.
  110 :
  120 cols%=20:rows%=8
  130 cw%=8:ch%=8
  140 md%=21:vdu%=0:pivdu%=2
  150 sim%=TRUE
  160 glass%=FALSE
  170 :
  180 tot%=0:bad%=0
  190 DIM buf% 80
  200 e$=CHR$(27)
  210 ON ERROR PROCerr:END
  220 PROCv_boot
  230 IF vfail$<>"" THEN PRINT "cannot start: ";vfail$:END
  240 PROCtests
  250 PRINT
  260 PRINT tot%-bad%;" of ";tot%;" checks passed"
  270 IF bad%=0 THEN PRINT "[parseok]" ELSE PRINT "[parsebad]"
  280 END
  290 :
10000 DEF PROCtests
10010 PROCt_text
10020 PROCt_wrap
10030 PROCt_move
10040 PROCt_erase
10050 PROCt_edit
10060 PROCt_region
10070 PROCt_sgr
10080 PROCt_alt
10090 PROCt_reply
10100 PROCt_utf8
10110 PROCt_line
10120 PROCt_misc
10130 ENDPROC
10140 :
10150 REM ---- text, and the C0 codes -------------------------------------
10160 DEF PROCt_text
10170 PROCfresh
10180 PROCw("hello")
10190 PROCeq("plain text","hello...............",FNrow(0))
10200 PROCeq("cursor after text","5",STR$(cx%))
10210 PROCw(CHR$(13)+"HE")
10220 PROCeq("cr returns to column 0","HEllo...............",FNrow(0))
10230 PROCfresh
10240 PROCw("a"+CHR$(10)+"b")
10250 PROCeq("lf does not return","a...................",FNrow(0))
10260 PROCeq("lf moved down",".b..................",FNrow(1))
10270 PROCeq("lf kept the column","2",STR$(cx%))
10280 PROCfresh
10290 PROCw("abc"+CHR$(8)+"X")
10300 PROCeq("backspace","abX.................",FNrow(0))
10310 PROCfresh
10320 PROCw("a"+CHR$(9)+"b"+CHR$(9)+"c")
10330 PROCeq("tab stops every eight","a.......b.......c...",FNrow(0))
10340 ENDPROC
10350 :
10360 REM ---- the pending wrap -------------------------------------------
10370 REM The rule 9.3 could not implement and paid for twice: a glyph in
10380 REM the last column does not move the cursor, so the cursor is still
10390 REM ON the character, and only the NEXT glyph wraps.
10400 DEF PROCt_wrap
10410 PROCfresh
10420 PROCw(STRING$(20,"x"))
10430 PROCeq("full line stays on row 0","0",STR$(cy%))
10440 PROCeq("cursor sits on the last column","19",STR$(cx%))
10450 PROCw("y")
10460 PROCeq("the next glyph wraps","1",STR$(cy%))
10470 PROCeq("and lands in column 1","1",STR$(cx%))
10480 PROCeq("wrapped row","y...................",FNrow(1))
10490 PROCfresh
10500 PROCw(STRING$(20,"x")+CHR$(13)+"z")
10510 PROCeq("cr cancels the pending wrap","0",STR$(cy%))
10520 PROCeq("cr cancelled row","zxxxxxxxxxxxxxxxxxxx",FNrow(0))
10530 PROCfresh
10540 PROCw(STRING$(20,"x")+CHR$(10))
10550 PROCeq("lf after a full line moves one row","1",STR$(cy%))
10560 PROCfresh
10570 PROCw(e$+"[?7l"+STRING$(22,"x"))
10580 PROCeq("autowrap off overwrites","xxxxxxxxxxxxxxxxxxxx",FNrow(0))
10590 PROCeq("autowrap off stays on row 0","0",STR$(cy%))
10600 PROCw(e$+"[?7h")
10610 ENDPROC
10620 :
10630 REM ---- cursor movement --------------------------------------------
10640 DEF PROCt_move
10650 PROCfresh
10660 PROCw(e$+"[3;5H"+"X")
10670 PROCeq("cup is one based","....X...............",FNrow(2))
10680 PROCw(e$+"[H"+"Y")
10690 PROCeq("cup with no parameters homes","Y...................",FNrow(0))
10700 PROCfresh
10710 PROCw(e$+"[5;5H"+e$+"[2A"+"U")
10720 PROCeq("cuu","....U...............",FNrow(2))
10730 PROCw(e$+"[3B"+"D")
10740 PROCeq("cud",".....D..............",FNrow(5))
10750 PROCfresh
10760 PROCw(e$+"[1;1H"+e$+"[4C"+"R")
10770 PROCeq("cuf","....R...............",FNrow(0))
10780 PROCw(e$+"[3D"+"L")
10790 PROCeq("cub","..L.R...............",FNrow(0))
10800 PROCfresh
10810 PROCw(e$+"[4;1H"+e$+"[7G"+"G")
10820 PROCeq("cha","......G.............",FNrow(3))
10830 PROCw(e$+"[6d"+"V")
10840 PROCeq("vpa keeps the column",".......V............",FNrow(5))
10850 PROCfresh
10860 PROCw(e$+"[99;99H"+"C")
10870 PROCeq("cup clamps to the corner","...................C",FNrow(7))
10880 ENDPROC
10890 :
10900 REM ---- erasing ----------------------------------------------------
10910 DEF PROCt_erase
10920 PROCfresh
10930 PROCw("abcdefgh"+e$+"[1;4H"+e$+"[K")
10940 PROCeq("el 0","abc.................",FNrow(0))
10950 PROCfresh
10960 PROCw("abcdefgh"+e$+"[1;4H"+e$+"[1K")
10970 PROCeq("el 1","....efgh............",FNrow(0))
10980 PROCfresh
10990 PROCw("abcdefgh"+e$+"[2K")
11000 PROCeq("el 2","....................",FNrow(0))
11010 PROCfresh
11020 PROCw("aaa"+CHR$(13)+CHR$(10)+"bbb"+CHR$(13)+CHR$(10)+"ccc")
11030 PROCw(e$+"[2;2H"+e$+"[J")
11040 PROCeq("ed 0 keeps the row above","aaa.................",FNrow(0))
11050 PROCeq("ed 0 clears below","....................",FNrow(2))
11060 PROCfresh
11070 PROCw("aaa"+CHR$(13)+CHR$(10)+"bbb"+CHR$(13)+CHR$(10)+"ccc")
11080 PROCw(e$+"[2;2H"+e$+"[1J")
11090 PROCeq("ed 1 clears above","....................",FNrow(0))
11100 PROCeq("ed 1 keeps below","ccc.................",FNrow(2))
11110 PROCfresh
11120 PROCw("aaa"+e$+"[2J")
11130 PROCeq("ed 2","....................",FNrow(0))
11140 ENDPROC
11150 :
11160 REM ---- the editing sequences --------------------------------------
11170 DEF PROCt_edit
11180 PROCfresh
11190 PROCw("abcdefgh"+e$+"[1;3H"+e$+"[3@")
11200 PROCeq("ich","ab...cdefgh.........",FNrow(0))
11210 PROCfresh
11220 PROCw("abcdefgh"+e$+"[1;3H"+e$+"[3P")
11230 PROCeq("dch","abfgh...............",FNrow(0))
11240 PROCfresh
11250 PROCw("abcdefgh"+e$+"[1;3H"+e$+"[3X")
11260 PROCeq("ech","ab...fgh............",FNrow(0))
11270 PROCfresh
11280 PROCw("abcdefgh"+e$+"[1;3H"+e$+"[4h"+"XY"+e$+"[4l")
11290 PROCeq("insert mode","abXYcdefgh..........",FNrow(0))
11300 PROCdigits
11310 PROCw(e$+"[4;1H"+e$+"[L")
11320 PROCeq("il","012.3456",FNsig)
11330 PROCdigits
11340 PROCw(e$+"[4;1H"+e$+"[M")
11350 PROCeq("dl","0124567.",FNsig)
11360 ENDPROC
11370 :
11380 REM ---- the scrolling region ---------------------------------------
11390 DEF PROCt_region
11400 PROCdigits
11410 PROCw(e$+"[3;6r")
11420 PROCeq("decstbm homes the cursor","0 0",STR$(cx%)+" "+STR$(cy%))
11430 PROCdigits
11440 PROCw(e$+"[3;6r"+e$+"[6;1H"+CHR$(10))
11450 PROCeq("lf at the region foot scrolls it","01345.67",FNsig)
11460 PROCeq("and left the cursor there","5",STR$(cy%))
11470 PROCdigits
11480 PROCw(e$+"[3;6r"+e$+"[3;1H"+e$+"M")
11490 PROCeq("reverse index at the region head","01.23467",FNsig)
11500 PROCdigits
11510 PROCw(e$+"[3;6r"+e$+"[2S")
11520 PROCeq("su inside the region","0145..67",FNsig)
11530 PROCdigits
11540 PROCw(e$+"[3;6r"+e$+"[?6h"+"O")
11550 PROCeq("origin mode homes to the region","O...................",FNrow(2))
11560 PROCw(e$+"[99;1H"+"B")
11570 PROCeq("origin mode confines the cursor","B...................",FNrow(5))
11580 PROCw(e$+"[?6l"+e$+"[r")
11590 ENDPROC
11600 :
11610 REM ---- SGR --------------------------------------------------------
11620 DEF PROCt_sgr
11630 PROCfresh
11640 PROCw(e$+"[31;44m"+"c")
11650 PROCeq("ansi colours","1 4",FNfg(0,0)+" "+FNbg(0,0))
11660 PROCw(e$+"[0m"+"d")
11670 PROCeq("sgr 0 resets","7 0",FNfg(1,0)+" "+FNbg(1,0))
11680 PROCw(e$+"[93;103m"+"e")
11690 PROCeq("bright colours are 8 to 15","11 11",FNfg(2,0)+" "+FNbg(2,0))
11700 PROCw(e$+"[38;5;196;48;5;17m"+"f")
11710 PROCeq("256 colour is exact","196 17",FNfg(3,0)+" "+FNbg(3,0))
11720 PROCw(e$+"[38;2;255;0;0m"+"g")
11730 PROCeq("truecolour reduces to the cube","196",FNfg(4,0))
11740 PROCw(e$+"[0;1;4;7;9m"+"h")
11750 PROCeq("all four attributes","15",FNfl(5,0))
11760 PROCw(e$+"[22;24;27;29m"+"i")
11770 PROCeq("and each turns off","0",FNfl(6,0))
11780 PROCfresh
11790 PROCw(e$+"[44m"+e$+"[2K")
11800 PROCeq("bce - an erase paints the background","4444444444",FNbgs(0,10))
11810 PROCw(e$+"[0m")
11820 ENDPROC
11830 :
11840 REM ---- the alternate screen ---------------------------------------
11850 REM 9.3 could only clear on the way in and clear again on the way
11860 REM out. This is a real second buffer, so what was behind comes back.
11870 DEF PROCt_alt
11880 PROCfresh
11890 PROCw("main screen")
11900 PROCw(e$+"[?1049h")
11910 PROCeq("alt starts clear","....................",FNrow(0))
11920 PROCw("alternate")
11930 PROCeq("alt holds its own text","alternate...........",FNrow(0))
11940 PROCw(e$+"[?1049l")
11950 PROCeq("and the main screen comes back","main.screen.........",FNrow(0))
11960 PROCeq("with the cursor where it was","11",STR$(cx%))
11970 ENDPROC
11980 :
11990 REM ---- the reply channel ------------------------------------------
12000 DEF PROCt_reply
12010 PROCfresh
12020 PROCw(e$+"[3;5H"+e$+"[6n")
12030 PROCeq("cursor position report","[3;5R",FNreply)
12040 PROCw(e$+"[5n")
12050 PROCeq("device status report","[0n",FNreply)
12060 PROCw(e$+"[c")
12070 PROCeq("device attributes","[?6c",FNreply)
12080 PROCeq("reading clears the buffer","",FNreply)
12090 ENDPROC
12100 :
12110 REM ---- UTF-8 ------------------------------------------------------
12120 DEF PROCt_utf8
12130 PROCfresh
12140 PROCw("a"+CHR$(&C2)+CHR$(&B7)+"b")
12150 PROCeq("two byte sequence is one cell","3",STR$(cx%))
12160 PROCeq("middle dot maps to the graphics set","159",STR$(FNg(1,0)))
12170 PROCfresh
12180 PROCw(CHR$(&E2)+CHR$(&94)+CHR$(&80))
12190 PROCeq("three byte box drawing","146",STR$(FNg(0,0)))
12200 PROCfresh
12210 PROCw(CHR$(&E2)+CHR$(&96)+CHR$(&91))
12220 PROCeq("unmapped codepoint is the replacement","63",STR$(FNg(0,0)))
12230 PROCfresh
12240 PROCw(CHR$(&C2)+"A")
12250 PROCeq("a broken sequence costs one glyph","63",STR$(FNg(0,0)))
12260 PROCeq("and the byte that broke it is kept","65",STR$(FNg(1,0)))
12270 ENDPROC
12280 :
12290 REM ---- the DEC line drawing set -----------------------------------
12300 DEF PROCt_line
12310 PROCfresh
12320 PROCw(e$+"(0"+"lqk")
12330 PROCeq("esc ( 0 maps 5F-7E","141 146 140",STR$(FNg(0,0))+" "+STR$(FNg(1,0))+" "+STR$(FNg(2,0)))
12340 PROCw(e$+"(B"+"lqk")
12350 PROCeq("esc ( B puts ascii back","108 113 107",STR$(FNg(3,0))+" "+STR$(FNg(4,0))+" "+STR$(FNg(5,0)))
12360 PROCfresh
12370 PROCw(e$+"(0"+CHR$(15)+"q")
12380 PROCeq("si selects g0","146",STR$(FNg(0,0)))
12390 PROCw(CHR$(14)+"q")
12400 PROCeq("so selects g1, still ascii","113",STR$(FNg(1,0)))
12410 PROCw(CHR$(15)+e$+"(B")
12420 ENDPROC
12430 :
12440 REM ---- the rest ---------------------------------------------------
12450 DEF PROCt_misc
12460 PROCfresh
12470 PROCw(e$+"#8")
12480 PROCeq("decaln fills the screen","EEEEEEEEEEEEEEEEEEEE",FNrow(4))
12490 PROCfresh
12500 PROCw("keep"+e$+"7"+e$+"[5;5H"+"lost"+e$+"8"+"X")
12510 PROCeq("decsc and decrc","keepX...............",FNrow(0))
12520 PROCfresh
12530 PROCw("abc"+e$+"]0;a title"+CHR$(7)+"def")
12540 PROCeq("osc is swallowed whole","abcdef..............",FNrow(0))
12550 PROCfresh
12560 PROCw("abc"+e$+"]0;title"+e$+"\"+"def")
12570 PROCeq("osc ended by st","abcdef..............",FNrow(0))
12580 PROCfresh
12590 PROCw(e$+"[31m"+"abc"+e$+"c"+"d")
12600 PROCeq("ris clears the screen","d...................",FNrow(0))
12610 PROCeq("ris resets the colour","7",FNfg(0,0))
12620 ENDPROC
12630 :
12640 REM ---- fixtures and assertions ------------------------------------
12650 DEF PROCfresh
12660 PROCv_writes(e$+"c")
12670 ENDPROC
12680 :
12690 DEF PROCdigits
12700 LOCAL y%
12710 PROCfresh
12720 FOR y%=0 TO rows%-1:PROCv_put(0,y%,48+y%,7,0,0):NEXT
12730 ENDPROC
12740 :
12750 DEF PROCw(s$)
12760 PROCv_writes(s$)
12770 ENDPROC
12780 :
12790 DEF FNrow(y%)
12800 LOCAL i%,c%
12810 FOR i%=0 TO cols%-1
12820   c%=?(scr%+((y%*cols%+i%)*4))
12830   IF c%=32 THEN c%=46
12840   buf%?i%=c%
12850 NEXT
12860 buf%?cols%=13
12870 =$buf%
12880 :
12890 DEF FNsig
12900 LOCAL y%,c%
12910 FOR y%=0 TO rows%-1
12920   c%=?(scr%+((y%*cols%)*4))
12930   IF c%=32 THEN c%=46
12940   buf%?y%=c%
12950 NEXT
12960 buf%?rows%=13
12970 =$buf%
12980 :
12990 DEF FNg(x%,y%)
13000 =?(scr%+((y%*cols%+x%)*4))+(?(scr%+((y%*cols%+x%)*4)+1) AND 15)*256
13010 :
13020 DEF FNfg(x%,y%)
13030 =STR$(?(scr%+((y%*cols%+x%)*4)+2))
13040 :
13050 DEF FNbg(x%,y%)
13060 =STR$(?(scr%+((y%*cols%+x%)*4)+3))
13070 :
13080 DEF FNfl(x%,y%)
13090 =STR$(?(scr%+((y%*cols%+x%)*4)+1) DIV 16)
13100 :
13110 DEF FNbgs(y%,n%)
13120 LOCAL i%
13130 FOR i%=0 TO n%-1:buf%?i%=48+?(scr%+((y%*cols%+i%)*4)+3):NEXT
13140 buf%?n%=13
13150 =$buf%
13160 :
13170 REM The reply with its ESC dropped, so a failure prints legibly.
13180 DEF FNreply
13190 LOCAL s$,t$,i%,c%
13200 s$=FNv_reply
13210 t$=""
13220 FOR i%=1 TO LEN(s$)
13230   c%=ASC(MID$(s$,i%,1))
13240   IF c%>31 THEN t$=t$+CHR$(c%)
13250 NEXT
13260 =t$
13270 :
13280 DEF PROCeq(n$,w$,g$)
13290 tot%=tot%+1
13300 IF g$=w$ THEN PRINT "pass  ";n$:ENDPROC
13310 bad%=bad%+1
13320 PRINT "FAIL  ";n$
13330 PRINT "      want [";w$;"]"
13340 PRINT "      got  [";g$;"]"
13350 ENDPROC
13360 :
13370 DEF PROCerr
13380 PRINT
13390 PRINT "Error ";ERR;" at line ";ERL;" in stage ";stage%
13400 REPORT:PRINT
13410 PRINT "[parsebad]"
13420 ENDPROC
