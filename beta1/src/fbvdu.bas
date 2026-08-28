 1000 REM > FBVDU - a terminal VDU that owns the Pi framebuffer
 1002 REM
 1004 REM The engine, and only the engine. It defines procedures and
 1006 REM declares no top level, so it is loaded UNDER a driver that
 1008 REM supplies lines 10-990: test/fbvt.bas here, PTERM in phase 5.
 1010 REM The driver chooses the geometry and calls PROCv_boot.
 1012 REM
 1014 REM   *EXEC FBVDU  then  *EXEC FBVT  then  RUN
 1016 REM
 1018 REM Split out of the single file at the start of phase 2, when the
 1020 REM VT parser roughly doubled the engine and phase 3 needed several
 1022 REM replay drivers standing on one copy of it.
 1024 REM
 1026 REM docs/fbvdu.md section 4 is the contract this implements, and the
 1028 REM contract is what a native co-processor core would be written
 1030 REM from, so the state lives in flat memory blocks that transliterate
 1032 REM to C arrays rather than in BASIC structures.
 1034 REM
 1036 REM ARM NATIVE ONLY on hardware - copro 15, reached with *ARMBASIC.
 1038 REM With sim%=TRUE it runs on any BBC BASIC, framebuffer and all.
 1040 :
 1042 REM ================ state, per docs/fbvdu.md 4 ================
 1044 REM One word per cell, and everything is in it, so damage is a
 1046 REM single word compare:
 1048 REM   byte 0  glyph, low 8 bits
 1050 REM   byte 1  bits 0-3 glyph high nibble; bits 4-7 flags
 1052 REM   byte 2  foreground, an xterm-256 index
 1054 REM   byte 3  background, an xterm-256 index
 1056 REM Flags: 1 reverse, 2 underline, 4 bold, 8 strike.
 1058 REM
 1060 REM 4096 glyphs is far more than the terminal will map and folding
 1062 REM the flags in buys a one-word compare in the flush, which runs
 1064 REM over every cell whether anything changed or not.
 1066 REM
 1068 REM Every scalar the engine owns is set here, in one place, because
 1070 REM BASIC raises error 26 on a variable that was never assigned and
 1072 REM the first read of an unset mode flag would be a phase 2 bug
 1074 REM hunted in the parser.
 1076 DEF PROCv_boot
 1078 fb%=0:sz%=0:pit%=0
 1080 blkr%=0:blkc%=-1
 1082 scr%=0:shd%=0:font%=0:xp%=0
 1084 cf%=-1:cb%=-1
 1086 cx%=0:cy%=0:cvis%=FALSE:con%=FALSE
 1088 ccx%=0:ccy%=0
 1090 stage%=0:vfail$=""
 1092 REM The scrolling region, DECSTBM, zero based and inclusive, and
 1094 REM the current SGR attribute. Every erase in the engine paints
 1096 REM sf% on sb%, which is background colour erase - what a TUI
 1098 REM relies on when it clears inside a coloured panel.
 1100 top%=0:bot%=rows%-1
 1102 sf%=7:sb%=0:sfl%=0
 1104 REM The parser's own state. vst% is the state machine, u8n%/u8v% the
 1106 REM UTF-8 decoder, np%/prv%/vint% the CSI being collected, pw% the
 1108 REM PENDING WRAP - the real VT rule, and the reason neither of 9.3's
 1110 REM hacks is needed here: no sacrificed bottom-right cell and no
 1112 REM swallowed LF.
 1114 vst%=0:u8n%=0:u8v%=0
 1116 np%=0:prv%=0:vint%=0:oscp%=0:vchs%=0
 1118 pw%=FALSE
 1120 sv_x%=0:sv_y%=0:sv_f%=7:sv_b%=0:sv_l%=0:sv_g%=0
 1122 awm%=TRUE:ckm%=FALSE:dom%=FALSE:ins%=FALSE:bp%=FALSE
 1124 g0%=0:g1%=0:gl%=0
 1126 alt%=0:alton%=FALSE
 1128 rep$=""
 1130 vrep%=63:vpua%=63:nicon%=0:nmap%=0:nsym%=0
 1132 REM Scratch for PROCv_cell, deliberately NOT local to it. Measured
 1134 REM on hardware 2026-08-20: the renderer painted 14,133 cells/sec
 1136 REM where fbbench's bare blit managed 56,889, and the difference is
 1138 REM what a BASIC procedure call costs - nine LOCAL declarations
 1140 REM pushed and popped for every cell on the screen. These are the
 1142 REM same nine variables at module level, so the call carries none.
 1144 REM
 1146 REM Safe because PROCv_cell is not recursive and is the only user.
 1148 REM PROCv_ink, which it calls, declares its own LOCALs, and BASIC
 1150 REM restores those on exit.
 1152 va%=0:vs%=0:vc%=0:vg%=0:vf%=0:vb%=0:vl%=0:vt%=0:vr%=0
 1154 REM Default on. A driver may set it FALSE after PROCv_boot - nothing
 1156 REM is rendered before then, so there is no sentinel to keep.
 1158 fastblank%=TRUE
 1160 REM ops% records which operation last wrote each shadow entry, so a
 1162 REM cell whose pixels are wrong can say how its shadow got there:
 1164 REM   1 painted by the flush   4 set by PROCv_sync at init
 1166 REM   8 moved by a scroll up   16 moved by a scroll down
 1168 REM The scroll carries the source cell's code, so 9 means painted and
 1170 REM then scrolled. Off by default; a driver turns it on after boot.
 1172 trace%=FALSE:ops%=0
 1174 PROCv_init
 1176 ENDPROC
 1178 :
 1180 REM ================ initialisation ================
 1182 DEF PROCv_init
 1184 REM PROFILING COUNTERS. Owned by the engine so any driver can read them,
 1186 REM and initialised HERE so nothing can read one before it exists - which
 1188 REM is exactly the error 26 the usemv% flag produced. The client turns
 1190 REM profon% on after PROCv_boot returns.
 1192 profon%=FALSE
 1194 tscroll=0:nscroll%=0:tcells=0:ncells%=0:nwrite%=0
 1196 REM The last scroll's arguments, so a crash that follows one shows what
 1198 REM it was asked to do rather than only that it happened.
 1200 lst%=0:lsb%=0:lsn%=0:lsd%=0
 1202 stage%=1
 1204 IF NOT sim% THEN IF vdu%=1 THEN OSCLI("PIVDU "+STR$(pivdu%))
 1206 IF NOT sim% THEN MODE md%
 1208 REM We draw our own cursor. The driver's would blink over the top
 1210 REM of a cell we own, and be harvested into the font besides.
 1212 IF NOT sim% THEN VDU 23,1,0
 1214 stage%=2
 1216 IF NOT glass% THEN fb%=0:pit%=0:sz%=0
 1218 REM ELSE binds to the FIRST IF on the line in BBC BASIC, not to
 1220 REM the nearest one, so the two tests below are written flat.
 1222 REM As IF glass% THEN IF sim% THEN A ELSE B, a model-only run
 1224 REM took the ELSE and asked the VDU driver where the screen was.
 1226 IF glass% AND sim% THEN PROCv_fake
 1228 IF glass% AND NOT sim% THEN PROCv_vars
 1230 IF vfail$<>"" THEN ENDPROC
 1232 stage%=3
 1234 IF glass% THEN DIM font% 1360*ch%-1, xp% 63
 1236 DIM scr% cols%*rows%*4-1, shd% cols%*rows%*4-1
 1238 DIM ops% cols%*rows%-1
 1240 DIM par% 63, tab% cols%-1
 1242 PROCv_tabinit
 1244 stage%=4
 1246 IF glass% AND sim% THEN PROCv_load
 1248 IF glass% AND NOT sim% THEN PROCv_harvest
 1250 REM After the font arrives, never before: these overwrite slots the
 1252 REM harvest does not fill.
 1254 IF glass% THEN PROCv_glyphs:PROCv_extra:PROCv_braille:PROCv_icons:PROCv_block:PROCv_dbox:PROCv_legacy:PROCv_latin:PROCv_diag:PROCv_sym
 1256 stage%=5
 1258 IF NOT sim% THEN PROCv_pal
 1260 stage%=6
 1262 PROCv_asm
 1264 IF glass% THEN PROCv_wipe(0)
 1266 PROCv_cls(7,0)
 1268 PROCv_sync
 1270 stage%=0
 1272 ENDPROC
 1274 :
 1276 REM 148 SCREENSTART, 150 TOTALSCREENSIZE, 6 bytes per line. The
 1278 REM geometry is checked rather than assumed: a pitch too narrow for
 1280 REM the cell grid would write off the end of every row, and the
 1282 REM first symptom would be a diagonal smear, not an error.
 1284 DEF PROCv_vars
 1286 LOCAL q%,r%
 1288 DIM q% 31,r% 31
 1290 !q%=148:q%!4=150:q%!8=6:q%!12=-1
 1292 SYS "OS_ReadVduVariables",q%,r%
 1294 fb%=!r%:sz%=r%!4:pit%=r%!8
 1296 IF fb%=0 THEN vfail$="no framebuffer address":ENDPROC
 1298 IF pit%<cols%*cw% THEN vfail$="pitch "+STR$(pit%)+" too narrow for "+STR$(cols%)+" cells":ENDPROC
 1300 IF sz%<rows%*ch%*pit% THEN vfail$="screen too short for "+STR$(rows%)+" rows":ENDPROC
 1302 ENDPROC
 1304 :
 1306 REM ---- the simulated screen -------------------------------------
 1308 REM A DIMmed block standing in for the framebuffer, with a pitch
 1310 REM that is exactly the cell grid. Word-aligned because the blitter
 1312 REM stores words and cols%*cw% is a multiple of four.
 1314 DEF PROCv_fake
 1316 pit%=cols%*cw%
 1318 sz%=pit%*rows%*ch%
 1320 DIM fb% sz%-1
 1322 ENDPROC
 1324 :
 1326 REM The font fbfont harvested off the driver, loaded from a PIFONT
 1327 REM file so that what renders here renders on the Beeb, glyph for
 1328 REM glyph. NOT SHIPPED: those glyphs belong to the Pi's VDU driver
 1329 REM and are not redistributed here. Make your own with fbfont.bas,
 1330 REM which harvests it off your own machine - and note the engine
 1331 REM harvests at run time anyway, so only the sim% path needs it.
 1332 DEF PROCv_load
 1334 OSCLI("LOAD PIFONT "+STR$~font%)
 1336 ENDPROC
 1338 :
 1340 REM Print the simulated screen as characters: one per pixel, so a
 1342 REM glyph is legible and a blit that lands a row out or a column
 1344 REM short is visible rather than inferred.
 1346 DEF PROCv_dump(t$)
 1348 LOCAL x%,y%,a%,v%,s$
 1350 PRINT t$
 1352 FOR y%=0 TO rows%*ch%-1
 1354   s$=""
 1356   FOR x%=0 TO pit%-1
 1358     v%=fb%?(y%*pit%+x%)
 1360     IF v%=0 THEN s$=s$+"." ELSE s$=s$+CHR$(48+(v% MOD 10))
 1362   NEXT
 1364   PRINT s$
 1366 NEXT
 1368 ENDPROC
 1370 :
 1372 REM ---- the font, taken off the driver ---------------------------
 1374 REM Print a character, read the pixels back out of the framebuffer.
 1376 REM 101 glyphs in 1 cs on hardware, so this happens at every
 1378 REM startup and no font is ever transported. The six box pieces
 1380 REM are defined first because no BBC font carries them.
 1382 DEF PROCv_harvest
 1384 LOCAL c%,bg%
 1386 PROCv_box
 1388 VDU 17,15,17,128
 1390 CLS
 1392 bg%=fb%?0
 1394 FOR c%=32 TO 126:PROCv_grab(c%,bg%):NEXT
 1396 FOR c%=224 TO 229:PROCv_grab(c%,bg%):NEXT
 1398 ENDPROC
 1400 :
 1402 DEF PROCv_box
 1404 VDU 23,224,0,0,0,&1F,&18,&18,&18,&18
 1406 VDU 23,225,0,0,0,&F8,&18,&18,&18,&18
 1408 VDU 23,226,&18,&18,&18,&1F,0,0,0,0
 1410 VDU 23,227,&18,&18,&18,&F8,0,0,0,0
 1412 VDU 23,228,0,0,0,&FF,0,0,0,0
 1414 VDU 23,229,&18,&18,&18,&18,&18,&18,&18,&18
 1416 ENDPROC
 1418 :
 1420 REM Bit 7 is the leftmost pixel, which fbfont confirmed on hardware
 1422 REM by harvesting the box pieces back byte-identical to their VDU
 1424 REM 23 definitions - a mirrored read would have turned &1F to &F8.
 1426 DEF PROCv_grab(c%,bg%)
 1428 LOCAL y%,i%,a%,b%,m%
 1430 VDU 31,2,2,c%
 1432 FOR y%=0 TO ch%-1
 1434   a%=fb%+(2*ch%+y%)*pit%+2*cw%
 1436   b%=0:m%=128
 1438   FOR i%=0 TO cw%-1
 1440     IF a%?i%<>bg% THEN b%=b%+m%
 1442     m%=m% DIV 2
 1444   NEXT
 1446   font%?(c%*ch%+y%)=b%
 1448 NEXT
 1450 ENDPROC
 1452 :
 1454 REM ---- the palette ----------------------------------------------
 1456 REM All 256 entries set to the true xterm-256 colours. fbpal2
 1458 REM proved on hardware that every entry is its own - entry 200
 1460 REM changed while entry 8 did not - so nothing is approximated and
 1462 REM FNx256's nearest-colour reduction is never written.
 1464 DEF PROCv_pal
 1466 LOCAL n%,i%,r%,g%,b%
 1468 RESTORE 1502
 1470 FOR n%=0 TO 15:READ r%,g%,b%:VDU 19,n%,16,r%,g%,b%:NEXT
 1472 FOR n%=16 TO 231
 1474   i%=n%-16
 1476   r%=FNcube(i% DIV 36):g%=FNcube((i% DIV 6) MOD 6):b%=FNcube(i% MOD 6)
 1478   VDU 19,n%,16,r%,g%,b%
 1480 NEXT
 1482 FOR n%=232 TO 255
 1484   g%=8+(n%-232)*10
 1486   VDU 19,n%,16,g%,g%,g%
 1488 NEXT
 1490 ENDPROC
 1492 :
 1494 DEF FNcube(v%)
 1496 IF v%=0 THEN =0
 1498 =55+40*v%
 1500 :
 1502 DATA 0,0,0, 170,0,0, 0,170,0, 170,85,0
 1504 DATA 0,0,170, 170,0,170, 0,170,170, 170,170,170
 1506 DATA 85,85,85, 255,85,85, 85,255,85, 255,255,85
 1508 DATA 85,85,255, 255,85,255, 85,255,255, 255,255,255
 1510 :
 1512 REM ================ the model ================
 1514 REM Writing a cell is four byte stores into one word. No packing
 1516 REM arithmetic: shifting a background above 127 into the top of a
 1518 REM word overflows BASIC's signed integer and raises Number too
 1520 REM big, and the byte stores are faster besides.
 1522 DEF PROCv_put(x%,y%,g%,f%,b%,fl%)
 1524 LOCAL a%
 1526 IF x%<0 OR y%<0 OR x%>=cols% OR y%>=rows% THEN ENDPROC
 1528 a%=scr%+(y%*cols%+x%)*4
 1530 a%?0=g% AND 255
 1532 a%?1=((g% DIV 256) AND 15) OR (fl%*16)
 1534 a%?2=f%
 1536 a%?3=b%
 1538 ENDPROC
 1540 :
 1542 DEF PROCv_text(x%,y%,s$,f%,b%,fl%)
 1544 LOCAL i%
 1546 FOR i%=1 TO LEN(s$)
 1548   PROCv_put(x%+i%-1,y%,ASC(MID$(s$,i%,1)),f%,b%,fl%)
 1550 NEXT
 1552 ENDPROC
 1554 :
 1556 DEF PROCv_cls(f%,b%)
 1558 LOCAL i%,a%
 1560 FOR i%=0 TO cols%*rows%-1
 1562   a%=scr%+i%*4
 1564   a%?0=32:a%?1=0:a%?2=f%:a%?3=b%
 1566 NEXT
 1568 ENDPROC
 1570 :
 1572 REM Fill the glass with one colour. The ink cache is invalidated
 1574 REM afterwards because xp% was borrowed to build the fill word.
 1576 DEF PROCv_wipe(b%)
 1578 LOCAL i%,w%,n%
 1580 FOR i%=0 TO 3:xp%?i%=b%:NEXT
 1582 w%=!xp%
 1584 n%=rows%*ch%*pit%
 1586 FOR i%=0 TO n%-4 STEP 4:fb%!i%=w%:NEXT
 1588 cf%=-1:cb%=-1
 1590 ENDPROC
 1592 :
 1594 REM Declare that the glass already shows the model, without
 1596 REM painting anything. A shadow that disagrees with the glass is
 1598 REM worse than no shadow at all - the flush would skip exactly the
 1600 REM cells that need painting - so this is correct only in the case
 1602 REM it is used for: straight after a wipe, where every cell is
 1604 REM blank, and a blank cell renders as its background whatever its
 1606 REM foreground happens to say.
 1608 DEF PROCv_sync
 1610 LOCAL i%
 1612 FOR i%=0 TO cols%*rows%-1:shd%!(i%*4)=scr%!(i%*4):NEXT
 1614 IF trace% THEN FOR i%=0 TO cols%*rows%-1:ops%?i%=4:NEXT
 1616 ENDPROC
 1618 :
 1620 REM ================ the renderer ================
 1622 REM xp% holds one word per nibble: the four pixel bytes that nibble
 1624 REM expands to for the current pair of colours. A glyph row is then
 1626 REM two lookups and two word stores, and a colour change costs 16
 1628 REM word writes rather than anything per cell. Rebuilt only when
 1630 REM the pair actually changes, which over a run of same-coloured
 1632 REM text is once.
 1634 DEF PROCv_ink(f%,b%)
 1636 LOCAL n%,i%,m%,a%
 1638 IF f%=cf% AND b%=cb% THEN ENDPROC
 1640 FOR n%=0 TO 15
 1642   a%=xp%+n%*4:m%=8
 1644   FOR i%=0 TO 3
 1646     IF (n% AND m%)<>0 THEN a%?i%=f% ELSE a%?i%=b%
 1648     m%=m% DIV 2
 1650   NEXT
 1652 NEXT
 1654 cf%=f%:cb%=b%
 1656 ENDPROC
 1658 :
 1660 REM One cell, straight from the model onto the glass. Unrolled over
 1662 REM the eight rows: fbbench could not separate the variants at one
 1664 REM repeat, but the unrolled form is never slower and this is the
 1666 REM procedure everything else spends its time in.
 1668 REM The same guard, and here it matters more: va% indexes the REAL
 1670 REM framebuffer, so an out-of-range cell does not corrupt a BASIC array,
 1672 REM it writes into the Pi's memory. That is a machine that stops rather
 1674 REM than a screen that looks wrong.
 1676 DEF PROCv_cell(x%,y%)
 1678 IF x%<0 OR y%<0 OR x%>=cols% OR y%>=rows% THEN ENDPROC
 1680 vc%=scr%+(y%*cols%+x%)*4
 1682 vg%=vc%?0+(vc%?1 AND 15)*256
 1684 vl%=vc%?1 DIV 16
 1686 vf%=vc%?2:vb%=vc%?3
 1688 IF (vl% AND 1)<>0 THEN vt%=vf%:vf%=vb%:vb%=vt%
 1690 IF (vl% AND 4)<>0 AND vf%<8 THEN vf%=vf%+8
 1692 PROCv_ink(vf%,vb%)
 1694 va%=fb%+y%*ch%*pit%+x%*cw%
 1696 REM A blank with nothing drawn over it is the commonest cell on any
 1698 REM terminal screen - every erase and every scroll makes rows of
 1700 REM them - and it needs no font lookup at all. Nibble 0 expands to
 1702 REM four bytes of background, so the cell is sixteen stores of one
 1704 REM value. Reverse has already been folded into the colours above.
 1706 REM fastblank% turns this off. Every stale cell on hardware has been
 1708 REM a BLANK - the model says clear, the flush sets the shadow to clear,
 1710 REM and the pixels keep the old character - and once one cell is
 1712 REM inconsistent a scroll carries it up the screen, which is why they
 1714 REM appear as stripes. This is the only path a blank takes that a
 1716 REM character does not, so switching it off says whether it is at
 1718 REM fault. Glyph 32 in the font is empty, so the general path paints
 1720 REM the same pixels; it just looks them up.
 1722 IF fastblank% AND vg%=32 AND (vl% AND 10)=0 THEN PROCv_blank:ENDPROC
 1724 vs%=font%+vg%*ch%
 1726 vr%=vs%?0:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1728 vr%=vs%?1:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1730 vr%=vs%?2:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1732 vr%=vs%?3:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1734 vr%=vs%?4:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1736 vr%=vs%?5:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1738 vr%=vs%?6:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1740 vr%=vs%?7:!va%=xp%!((vr% DIV 16)*4):va%!4=xp%!((vr% AND 15)*4):va%=va%+pit%
 1742 REM Underline and strike are drawn, not held in the font: a
 1744 REM terminal applies them to any glyph, and 15 is the all-ones
 1746 REM nibble, so a row of foreground is two stores.
 1748 IF (vl% AND 2)<>0 THEN vt%=va%-pit%:!vt%=xp%!60:vt%!4=xp%!60
 1750 IF (vl% AND 8)<>0 THEN vt%=va%-pit%*4:!vt%=xp%!60:vt%!4=xp%!60
 1752 ENDPROC
 1754 :
 1756 DEF PROCv_blank
 1758 LOCAL i%,w%
 1760 w%=!xp%
 1762 FOR i%=1 TO ch%
 1764   !va%=w%:va%!4=w%:va%=va%+pit%
 1766 NEXT
 1768 ENDPROC
 1770 :
 1772 REM ---- the flush ------------------------------------------------
 1774 REM The whole point of the model/renderer split. A drain's worth of
 1776 REM bytes is applied to the model, then this runs ONCE: it walks
 1778 REM every cell, blits only those that differ from what is already
 1780 REM on the glass, and records what it painted. Twenty scrolled
 1782 REM lines cost one flush, not twenty.
 1784 REM
 1786 REM The walk itself is 1 cs over 5120 cells (fbbench), so it is
 1788 REM cheap enough to be unconditional.
 1790 DEF FNv_flush
 1792 IF glass% THEN =FNv_flushg
 1794 =FNv_flushm
 1796 :
 1798 DEF FNv_flushg
 1800 LOCAL x%,y%,i%,n%,w%
 1802 n%=0
 1804 IF con% THEN PROCv_uncur
 1806 FOR y%=0 TO rows%-1
 1808   FOR x%=0 TO cols%-1
 1810     i%=(y%*cols%+x%)*4
 1812     w%=scr%!i%
 1814     IF w%<>shd%!i% THEN PROCv_cell(x%,y%):shd%!i%=w%:n%=n%+1:IF trace% THEN ops%?(i% DIV 4)=1
 1816   NEXT
 1818 NEXT
 1820 IF cvis% THEN PROCv_cur
 1822 =n%
 1824 :
 1826 REM The same accounting with nothing painted. Damage is still tracked
 1828 REM and still reported, so a model-only run measures exactly what a
 1830 REM rendering one would have repainted - which is the number the
 1832 REM phase 3 replays assert on.
 1834 DEF FNv_flushm
 1836 LOCAL i%,n%,w%
 1838 n%=0
 1840 FOR i%=0 TO (cols%*rows%-1)*4 STEP 4
 1842   w%=scr%!i%
 1844   IF w%<>shd%!i% THEN shd%!i%=w%:n%=n%+1
 1846 NEXT
 1848 =n%
 1850 :
 1852 REM How many cells in rows t% to b% differ from what is on the
 1854 REM glass. The flush would paint exactly these. Used by the tests
 1856 REM to make assertions about WHERE damage is, which is the only way
 1858 REM to check that the scroll kept the glass, the model and the
 1860 REM shadow in step.
 1862 DEF FNv_damage(t%,b%)
 1864 LOCAL x%,y%,i%,n%
 1866 n%=0
 1868 FOR y%=t% TO b%
 1870   FOR x%=0 TO cols%-1
 1872     i%=(y%*cols%+x%)*4
 1874     IF scr%!i%<>shd%!i% THEN n%=n%+1
 1876   NEXT
 1878 NEXT
 1880 =n%
 1882 :
 1884 REM Read the model back - one word, laid out as 4.1 describes.
 1886 REM Free here and impossible through the BBC driver, which is why
 1888 REM the phase 3 replays can diff a screen against pyte at all.
 1890 DEF FNv_cell(x%,y%)
 1892 IF x%<0 OR y%<0 OR x%>=cols% OR y%>=rows% THEN =0
 1894 =scr%!((y%*cols%+x%)*4)
 1896 :
 1898 REM ---- the cursor -----------------------------------------------
 1900 REM Drawn by re-blitting its cell with the colours swapped, and
 1902 REM erased by blitting it normally. It is never in the model, so it
 1904 REM cannot be scrolled, saved or read back by mistake - it is a
 1906 REM property of the display, which is what a cursor is.
 1908 REM WHERE the cursor was drawn is remembered, because by the time it is
 1910 REM erased the cursor has moved. The flush draws it at the end and
 1912 REM erases it at the start of the NEXT flush - and in between a whole
 1914 REM drain of bytes has run, so cx% and cy% are somewhere else entirely.
 1916 REM
 1918 REM Erasing at the new position repaints a cell that did not need it and
 1920 REM leaves the old one inverted on the glass, while the shadow says that
 1922 REM cell is already correct - so the flush can never remove it. It is
 1924 REM permanent, and it is one stale block per cursor movement.
 1926 REM
 1928 REM Every offline test ran with cvis%=FALSE. The cursor is off in the
 1930 REM replays and on in real use, which is why an oracle that got 5120
 1932 REM cells right four times never saw this.
 1934 DEF PROCv_cur
 1936 LOCAL a%
 1938 IF NOT glass% OR cx%>=cols% OR cy%>=rows% OR cx%<0 OR cy%<0 THEN ENDPROC
 1940 ccx%=cx%:ccy%=cy%
 1942 a%=scr%+(ccy%*cols%+ccx%)*4
 1944 a%?1=a%?1 EOR 16
 1946 PROCv_cell(ccx%,ccy%)
 1948 a%?1=a%?1 EOR 16
 1950 REM AND TELL THE SHADOW. The glass at this cell now shows the cursor
 1952 REM and not what the model says, so the shadow is made to disagree with
 1954 REM the model - which forces the next flush to repaint it whatever
 1956 REM happens in between.
 1958 REM
 1960 REM Without this the cursor relies on PROCv_uncur being reached before
 1962 REM anything else touches the cell, and on hardware it is not always:
 1964 REM a live session left about a hundred and thirty cells showing old
 1966 REM characters that the flush believed were already correct, and the
 1968 REM same session with cvis%=FALSE left NONE. The shadow's whole job is
 1970 REM to describe the glass, and while the cursor is drawn it did not.
 1972 shd%!((ccy%*cols%+ccx%)*4)=NOT a%!0
 1974 con%=TRUE
 1976 ENDPROC
 1978 :
 1980 DEF PROCv_uncur
 1982 IF glass% AND con% THEN PROCv_cell(ccx%,ccy%)
 1984 con%=FALSE
 1986 ENDPROC
 1988 :
 1990 DEF PROCv_goto(x%,y%)
 1992 cx%=x%:cy%=y%
 1994 ENDPROC
 1996 :
 1998 REM ---- scrolling ------------------------------------------------
 2000 REM Rows t% to b% move up by n%. fbbench measured a screen move at
 2002 REM 4 cs against 9 to repaint, so the pixels are moved rather than
 2004 REM redrawn - and the shadow is moved with them, so the flush does
 2006 REM not then repaint the very rows that just arrived. Only the
 2008 REM exposed rows are left differing, which is exactly right.
 2010 REM
 2012 REM t%=b% is legal and means "clear the one row", which is what IL
 2014 REM and DL do with the cursor on the last row of the region.
 2016 REM
 2018 REM The moves live in PROCv_up and PROCv_down rather than inline
 2020 REM because a BBC FOR always runs its body once: scrolling a region
 2022 REM by its own full height gives a zero-length move, and the loop
 2024 REM would have copied one row from outside the region. Guarding the
 2026 REM CALL, not the loop, is the only way to express "do this no
 2028 REM times" in BASIC.
 2030 DEF PROCv_scroll(t%,b%,n%,f%,bg%)
 2032 LOCAL h%,pt
 2034 IF profon% THEN pt=TIME
 2036 IF n%<1 OR t%>b% OR t%<0 OR b%>rows%-1 THEN ENDPROC
 2038 IF n%>b%-t%+1 THEN n%=b%-t%+1
 2040 IF con% THEN PROCv_uncur
 2042 h%=b%-t%+1-n%
 2044 IF profon% THEN lst%=t%:lsb%=b%:lsn%=n%:lsd%=0
 2046 IF h%>0 THEN PROCv_up(t%,n%,h%)
 2048 PROCv_fill(b%-n%+1,b%,f%,bg%)
 2050 IF glass% THEN PROCv_clrg(b%-n%+1,b%,f%,bg%)
 2052 IF profon% THEN tscroll=tscroll+(TIME-pt):nscroll%=nscroll%+1
 2054 ENDPROC
 2056 :
 2058 REM The same, downwards, for reverse index, IL and SD. Both loops
 2060 REM run from the far end so that a move shorter than the distance
 2062 REM does not overwrite its own source.
 2064 DEF PROCv_sdown(t%,b%,n%,f%,bg%)
 2066 LOCAL h%,pt
 2068 IF profon% THEN pt=TIME
 2070 IF n%<1 OR t%>b% OR t%<0 OR b%>rows%-1 THEN ENDPROC
 2072 IF n%>b%-t%+1 THEN n%=b%-t%+1
 2074 IF con% THEN PROCv_uncur
 2076 h%=b%-t%+1-n%
 2078 IF profon% THEN lst%=t%:lsb%=b%:lsn%=n%:lsd%=1
 2080 IF h%>0 THEN PROCv_down(t%,n%,h%)
 2082 PROCv_fill(t%,t%+n%-1,f%,bg%)
 2084 IF profon% THEN tscroll=tscroll+(TIME-pt):nscroll%=nscroll%+1
 2086 ENDPROC
 2088 :
 2090 REM h% rows starting at t% move up by n% - glass, model and shadow.
 2092 DEF PROCv_up(t%,n%,h%)
 2094 LOCAL d%,s%,e%,o%
 2096 o%=shd%-scr%
 2098 IF glass% THEN PROCv_upg(t%,n%,h%)
 2100 REM Pointer arithmetic, not an index multiply per cell. A scroll moves
 2102 REM up to 63 rows of 80 cells across two arrays and runs on every
 2104 REM newline at the foot of the screen, so it is the other half of what
 2106 REM phase 3 found.
 2108 d%=scr%+t%*cols%*4
 2110 s%=d%+n%*cols%*4
 2112 REM Both arrays are contiguous, so this is two block moves rather than
 2114 REM 5,040 interpreted passes. The interpreted loop stays for trace%,
 2116 REM which has to OR a scroll mark into ops% cell by cell and cannot be
 2118 REM expressed as a move.
 2120 IF fastmv% AND NOT trace% THEN PROCv_up2(d%,s%,h%*cols%*4,o%):ENDPROC
 2122 e%=d%+h%*cols%*4
 2124 REPEAT
 2126   !d%=!s%
 2128   d%!o%=s%!o%
 2130   IF trace% THEN ops%?((d%-scr%) DIV 4)=ops%?((s%-scr%) DIV 4) OR 8
 2132   d%=d%+4:s%=s%+4
 2134 UNTIL d%>=e%
 2136 ENDPROC
 2138 :
 2140 DEF PROCv_down(t%,n%,h%)
 2142 LOCAL d%,s%,e%,o%
 2144 o%=shd%-scr%
 2146 IF glass% THEN PROCv_downg(t%,n%,h%)
 2148 s%=scr%+(t%+h%)*cols%*4-4
 2150 d%=s%+n%*cols%*4
 2152 e%=scr%+t%*cols%*4
 2154 REPEAT
 2156   !d%=!s%
 2158   d%!o%=s%!o%
 2160   IF trace% THEN ops%?((d%-scr%) DIV 4)=ops%?((s%-scr%) DIV 4) OR 16
 2162   d%=d%-4:s%=s%-4
 2164 UNTIL s%<e%
 2166 ENDPROC
 2168 :
 2170 REM The pixel half of a scroll. Separated from the row move so that a
 2172 REM model-only run - phase 3, where there is no framebuffer at all -
 2174 REM shares every line of the index arithmetic with the rendering one
 2176 REM and differs only in whether the glass is touched.
 2178 REM ASSEMBLE THE BLOCK MOVE. This is the hottest loop in the whole
 2180 REM terminal by an enormous margin and it was interpreted.
 2182 REM
 2184 REM Measured in a live session: a read inside a burst took 29.2ms and
 2186 REM returned 56 bytes, while the socket call it contains is 3.28ms. So
 2188 REM 89% of every read was our own code, and the burst rate came out at
 2190 REM 1921 bytes/sec against a path that can carry about 17,000.
 2192 REM
 2194 REM It is all here. The old PROCv_upg ran cols%*cw%/4 word copies per
 2196 REM pixel row across h%*ch% rows - 80,640 interpreted iterations - and it
 2198 REM runs on EVERY newline at the foot of the screen. cat a file and that
 2200 REM is once a line, inside the parse, inside the pump.
 2202 REM
 2204 REM This is the row-pointer scroll from the plan, which I demoted after
 2206 REM phase 4 measured 105 cells a flush. That measurement was of the
 2208 REM FLUSH, and the scroll is not in the flush - so it was demoted on
 2210 REM evidence that did not apply to it.
 2212 REM
 2214 REM Four words a pass. Every scroll length is a multiple of pit% (640),
 2216 REM which is a multiple of 16, so there is never a remainder to handle.
 2218 REM PARAMETERS IN MEMORY, NOT IN REGISTERS.
 2220 REM
 2222 REM The obvious way is CALL with A% B% C% and let BASIC put them in R0
 2224 REM R1 R2. That worked under b-em's Sprow ARM BASIC - but PiTubeDirect's
 2226 REM ARM BASIC is a different implementation, and if it does not set those
 2228 REM registers then STMIA R0! writes 320K to whatever R0 happened to hold.
 2230 REM That is a crash, not a wrong answer, and it is not worth assuming.
 2232 REM
 2234 REM So the routine loads its own arguments from prm%, whose address is
 2236 REM assembled in as a literal. The only thing CALL has to do is jump
 2238 REM there and leave a return address in R14, which is universal.
 2240 REM
 2242 REM And it is PROVED before it is trusted: a 64 byte move against a known
 2244 REM pattern, checked byte by byte. fastmv% stays FALSE if anything is
 2246 REM wrong and every caller falls back to the interpreted loop, so a BASIC
 2248 REM that does something unexpected costs speed and never correctness.
 2250 DEF PROCv_asm
 2252 LOCAL P%,opt%,i%,ok%
 2254 DIM mv% 127, prm% 11, ts% 63, td% 63
 2256 fastmv%=FALSE
 2258 FOR opt%=0 TO 2 STEP 2
 2260 P%=mv%
 2262 [OPT opt%
 2264 .mvblock
 2266 STMFD R13!,{R0-R6,R8-R12,R14}
 2268 LDR R12,pp
 2270 LDR R0,[R12,#0]
 2272 LDR R1,[R12,#4]
 2274 LDR R2,[R12,#8]
 2276 CMP R2,#64
 2278 BLT mvtail
 2280 .mvloop
 2282 LDMIA R1!,{R3-R6,R8-R11}
 2284 STMIA R0!,{R3-R6,R8-R11}
 2286 LDMIA R1!,{R3-R6,R8-R11}
 2288 STMIA R0!,{R3-R6,R8-R11}
 2290 SUBS R2,R2,#64
 2292 CMP R2,#64
 2294 BGE mvloop
 2296 .mvtail
 2298 CMP R2,#0
 2300 BLE mvdone
 2302 .mvtl
 2304 LDRB R3,[R1],#1
 2306 STRB R3,[R0],#1
 2308 SUBS R2,R2,#1
 2310 BGT mvtl
 2312 .mvdone
 2314 LDMFD R13!,{R0-R6,R8-R12,R14}
 2316 MOV PC,R14
 2318 .pp
 2320 EQUD prm%
 2322 ]
 2324 NEXT
 2326 ok%=TRUE
 2328 FOR i%=0 TO 63:ts%?i%=i%+1:td%?i%=0:NEXT
 2330 PROCv_mv(td%,ts%,64)
 2332 FOR i%=0 TO 63
 2334   IF td%?i%<>i%+1 THEN ok%=FALSE
 2336 NEXT
 2338 REM That exercises the 64-byte path only. Every caller today passes a
 2340 REM multiple of 64 - h%*ch%*pit% is h%*5120, h%*cols%*4 is h%*320 - but
 2342 REM nothing enforces it, so the tail loop gets its own case rather than
 2344 REM being shipped untested. It must also not touch a byte past the end.
 2346 FOR i%=0 TO 63:ts%?i%=i%+65:td%?i%=255:NEXT
 2348 PROCv_mv(td%,ts%,37)
 2350 FOR i%=0 TO 36
 2352   IF td%?i%<>i%+65 THEN ok%=FALSE
 2354 NEXT
 2356 FOR i%=37 TO 63
 2358   IF td%?i%<>255 THEN ok%=FALSE
 2360 NEXT
 2362 fastmv%=ok%
 2364 ENDPROC
 2366 :
 2368 DEF PROCv_mv(d%,s%,l%)
 2370 prm%!0=d%:prm%!4=s%:prm%!8=l%
 2372 CALL mvblock
 2374 ENDPROC
 2376 :
 2378 REM The scrolled region is CONTIGUOUS when a pixel row is exactly the
 2380 REM stride, which it is here (pit%=cols%*cw%=640), so the whole thing is
 2382 REM one block move rather than one per row. The interpreted loop stays
 2384 REM for the case where it is not, because a padded stride would make a
 2386 REM single move silently wrong rather than merely slow.
 2388 DEF PROCv_up2(d%,s%,l%,o%)
 2390 PROCv_mv(d%,s%,l%)
 2392 PROCv_mv(d%+o%,s%+o%,l%)
 2394 ENDPROC
 2396 :
 2398 DEF PROCv_upg(t%,n%,h%)
 2400 LOCAL l%,i%,d%,s%
 2402 d%=fb%+t%*ch%*pit%
 2404 s%=d%+n%*ch%*pit%
 2406 IF fastmv% AND pit%=cols%*cw% THEN PROCv_mv(d%,s%,h%*ch%*pit%):ENDPROC
 2408 FOR l%=0 TO h%*ch%-1
 2410   d%=fb%+(t%*ch%+l%)*pit%
 2412   s%=d%+n%*ch%*pit%
 2414   FOR i%=0 TO cols%*cw%-4 STEP 4:d%!i%=s%!i%:NEXT
 2416 NEXT
 2418 ENDPROC
 2420 :
 2422 DEF PROCv_downg(t%,n%,h%)
 2424 LOCAL l%,i%,d%,s%
 2426 FOR l%=h%*ch%-1 TO 0 STEP -1
 2428   s%=fb%+(t%*ch%+l%)*pit%
 2430   d%=s%+n%*ch%*pit%
 2432   FOR i%=0 TO cols%*cw%-4 STEP 4:d%!i%=s%!i%:NEXT
 2434 NEXT
 2436 ENDPROC
 2438 :
 2440 REM Rows t% to b% become blanks in the given colours. Model only -
 2442 REM the flush paints them, because a fill is not a move and there is
 2444 REM nothing to be gained by touching the glass twice.
 2446 REM An erase carries the CURRENT RENDITION, not just the current colours:
 2448 REM sfl% goes into the cell, not zero. Phase 3 caught this against pyte -
 2450 REM top draws its column header as a full-width reverse-video bar and
 2452 REM clears to the end of the line, so with the flags zeroed the bar
 2454 REM stopped where the text stopped instead of running to the right
 2456 REM margin. Two cells out of 5120, and the kind of thing that looks like
 2458 REM "the colours are a bit off" on a photograph of a monitor.
 2460 REM
 2462 REM Written straight into scr% rather than through PROCv_put. A clear of
 2464 REM the whole screen is 5120 cells, and a BASIC procedure call per cell
 2466 REM made RIS and the alternate screen switch cost seconds each - phase 3
 2468 REM measured 582 bytes of capture taking 33 SECONDS, nearly all of it
 2470 REM here. The stores are the same four bytes either way.
 2472 DEF PROCv_fill(t%,b%,f%,bg%)
 2474 LOCAL a%,e%
 2476 IF b%<t% OR t%<0 OR b%>rows%-1 THEN ENDPROC
 2478 a%=scr%+t%*cols%*4
 2480 e%=scr%+(b%+1)*cols%*4
 2482 REPEAT
 2484   a%?0=32:a%?1=sfl%*16:a%?2=f%:a%?3=bg%
 2486   a%=a%+4
 2488 UNTIL a%>=e%
 2490 ENDPROC
 2492 :
 2494 REM ================ the editing operations ================
 2496 REM IL DL ICH DCH ECH ED EL SU SD - the sequences a TUI uses on
 2498 REM every frame and the BBC VDU driver has none of. Here they are
 2500 REM index arithmetic over scr%, which is the whole argument for
 2502 REM owning the cell model rather than driving a driver.
 2504 REM
 2506 REM They erase in the CURRENT SGR colours, not in the default ones.
 2508 REM That is background colour erase, what xterm advertises as bce,
 2510 REM and it is why clearing to end of line inside a coloured region
 2512 REM leaves the colour behind rather than a black gap.
 2514 :
 2516 REM The scrolling region, DECSTBM. Held zero-based and inclusive.
 2518 REM An empty or inverted region is not an error in the VT: it resets
 2520 REM to the whole screen, which is what a reset sequence relies on.
 2522 DEF PROCv_region(t%,b%)
 2524 IF t%<0 THEN t%=0
 2526 IF b%>rows%-1 THEN b%=rows%-1
 2528 IF b%<=t% THEN t%=0:b%=rows%-1
 2530 top%=t%:bot%=b%
 2532 ENDPROC
 2534 :
 2536 REM Erase a run of the current row. Every erase in the terminal ends
 2538 REM up here or in PROCv_fill.
 2540 DEF PROCv_erow(x1%,x2%)
 2542 LOCAL a%,e%
 2544 IF x2%<x1% OR cy%<0 OR cy%>rows%-1 THEN ENDPROC
 2546 IF x1%<0 THEN x1%=0
 2548 IF x2%>cols%-1 THEN x2%=cols%-1
 2550 a%=scr%+(cy%*cols%+x1%)*4
 2552 e%=scr%+(cy%*cols%+x2%)*4
 2554 REPEAT
 2556   a%?0=32:a%?1=sfl%*16:a%?2=sf%:a%?3=sb%
 2558   a%=a%+4
 2560 UNTIL a%>e%
 2562 ENDPROC
 2564 :
 2566 REM ICH - the rest of the line moves right, what falls off the right
 2568 REM margin is gone. Clamped so that inserting more than the line can
 2570 REM hold is a whole-line erase rather than an index off the end.
 2572 REM With a wrap PENDING, an operation that acts from the cursor acts from
 2574 REM PAST the last column and therefore does nothing. Phase 3 found this
 2576 REM against pyte and it was checked against tmux as a third opinion: top
 2578 REM writes an 80-character reverse-video header, resets the colour and
 2580 REM sends EL, and both leave all 80 cells reversed while this engine
 2582 REM erased the last one - a one-cell notch in the right-hand end of every
 2584 REM full-width bar. Verified the same way for ECH, ICH and DCH.
 2586 REM
 2588 REM pw% is only ever set with the cursor in the last column, so the guard
 2590 REM is just "not while a wrap is pending".
 2592 DEF PROCv_ich(n%)
 2594 IF n%<1 OR pw% THEN ENDPROC
 2596 IF n%>cols%-cx% THEN n%=cols%-cx%
 2598 IF cols%-cx%-n%>0 THEN PROCv_shr(n%)
 2600 PROCv_erow(cx%,cx%+n%-1)
 2602 ENDPROC
 2604 :
 2606 DEF PROCv_shr(n%)
 2608 LOCAL i%,a%
 2610 a%=scr%+cy%*cols%*4
 2612 FOR i%=cols%-1 TO cx%+n% STEP -1:a%!(i%*4)=a%!((i%-n%)*4):NEXT
 2614 ENDPROC
 2616 :
 2618 REM DCH - the rest of the line moves left, blanks arrive at the right
 2620 REM margin. The pair of them is how a line editor redraws one word.
 2622 DEF PROCv_dch(n%)
 2624 IF n%<1 OR pw% THEN ENDPROC
 2626 IF n%>cols%-cx% THEN n%=cols%-cx%
 2628 IF cols%-cx%-n%>0 THEN PROCv_shl(n%)
 2630 PROCv_erow(cols%-n%,cols%-1)
 2632 ENDPROC
 2634 :
 2636 DEF PROCv_shl(n%)
 2638 LOCAL i%,a%
 2640 a%=scr%+cy%*cols%*4
 2642 FOR i%=cx% TO cols%-1-n%:a%!(i%*4)=a%!((i%+n%)*4):NEXT
 2644 ENDPROC
 2646 :
 2648 REM ECH - erase in place. Nothing moves, which is what separates it
 2650 REM from DCH and is the difference between a cleared field and a
 2652 REM shortened line.
 2654 DEF PROCv_ech(n%)
 2656 IF n%<1 OR pw% THEN ENDPROC
 2658 IF n%>cols%-cx% THEN n%=cols%-cx%
 2660 PROCv_erow(cx%,cx%+n%-1)
 2662 ENDPROC
 2664 :
 2666 REM EL 0 to end of line, 1 to start inclusive of the cursor, 2 all.
 2668 DEF PROCv_el(m%)
 2670 IF m%=1 THEN PROCv_erow(0,cx%):ENDPROC
 2672 IF m%=2 THEN PROCv_erow(0,cols%-1):ENDPROC
 2674 IF pw% THEN ENDPROC
 2676 PROCv_erow(cx%,cols%-1)
 2678 ENDPROC
 2680 :
 2682 REM ED 0 to end of screen, 1 to the top, 2 all, 3 all plus the
 2684 REM scrollback - which we do not keep, so it is 2.
 2686 DEF PROCv_ed(m%)
 2688 IF m%>=2 THEN PROCv_fill(0,rows%-1,sf%,sb%):ENDPROC
 2690 IF m%=1 THEN PROCv_ed1:ENDPROC
 2692 PROCv_ed0
 2694 ENDPROC
 2696 :
 2698 DEF PROCv_ed0
 2700 IF NOT pw% THEN PROCv_erow(cx%,cols%-1)
 2702 IF cy%<rows%-1 THEN PROCv_fill(cy%+1,rows%-1,sf%,sb%)
 2704 ENDPROC
 2706 :
 2708 DEF PROCv_ed1
 2710 PROCv_erow(0,cx%)
 2712 IF cy%>0 THEN PROCv_fill(0,cy%-1,sf%,sb%)
 2714 ENDPROC
 2716 :
 2718 REM IL and DL act from the cursor row to the BOTTOM OF THE REGION,
 2720 REM not the bottom of the screen, and do nothing at all with the
 2722 REM cursor outside the region. Getting that wrong is what makes a
 2724 REM full-screen editor tear at the status line.
 2726 DEF PROCv_il(n%)
 2728 IF cy%<top% OR cy%>bot% THEN ENDPROC
 2730 PROCv_sdown(cy%,bot%,n%,sf%,sb%)
 2732 ENDPROC
 2734 :
 2736 DEF PROCv_dl(n%)
 2738 IF cy%<top% OR cy%>bot% THEN ENDPROC
 2740 PROCv_scroll(cy%,bot%,n%,sf%,sb%)
 2742 ENDPROC
 2744 :
 2746 REM SU and SD scroll the region itself and leave the cursor alone.
 2748 DEF PROCv_su(n%)
 2750 PROCv_scroll(top%,bot%,n%,sf%,sb%)
 2752 ENDPROC
 2754 :
 2756 DEF PROCv_sd(n%)
 2758 PROCv_sdown(top%,bot%,n%,sf%,sb%)
 2760 ENDPROC
 2762 :
 2764 REM Index and reverse index: move a row, scrolling the region only
 2766 REM when the cursor is already against its edge. Everything that
 2768 REM moves the screen - LF, NEL, IND, RI - comes through these two.
 2770 DEF PROCv_ind
 2772 IF cy%=bot% THEN PROCv_scroll(top%,bot%,1,sf%,sb%):ENDPROC
 2774 IF cy%<rows%-1 THEN cy%=cy%+1
 2776 ENDPROC
 2778 :
 2780 DEF PROCv_ri
 2782 IF cy%=top% THEN PROCv_sdown(top%,bot%,1,sf%,sb%):ENDPROC
 2784 IF cy%>0 THEN cy%=cy%-1
 2786 ENDPROC
 2788 REM ================ the DEC line drawing glyphs ================
 2790 REM Slots 128-159 hold the DEC special graphics set, reached with
 2792 REM ESC ( 0 and used by every ncurses program that draws a box. We
 2794 REM own the font table, so they are written straight into it - no
 2796 REM VDU 23, no harvest, and identical in simulation and on the glass.
 2798 REM
 2800 REM The stroke convention is the one fbfont already proved legible on
 2802 REM hardware: a horizontal on row 3, a vertical two pixels wide as
 2804 REM &18. The six glyphs PROCv_box defines are the same shapes, so a
 2806 REM box drawn through the line drawing set and one drawn through the
 2808 REM harvested pieces line up pixel for pixel.
 2810 DEF PROCv_glyphs
 2812 LOCAL c%,y%,b%
 2814 RESTORE 4070
 2816 FOR c%=&5F TO &7E
 2818   FOR y%=0 TO 7
 2820     READ b%
 2822     IF y%<ch% THEN font%?((128+c%-&5F)*ch%+y%)=b%
 2824   NEXT
 2826 NEXT
 2828 ENDPROC
 2830 :
 2832 REM ================ the stream ================
 2834 REM One byte in. Everything below this line is what 2.3a said the BBC
 2836 REM VDU driver could not be made to do.
 2838 DEF PROCv_write(c%)
 2840 IF vst%=0 THEN PROCv_ground(c%):ENDPROC
 2842 IF vst%=1 THEN PROCv_esc(c%):ENDPROC
 2844 IF vst%=2 THEN PROCv_csi(c%):ENDPROC
 2846 IF vst%=3 THEN PROCv_osc(c%):ENDPROC
 2848 IF vst%=4 THEN PROCv_str(c%):ENDPROC
 2850 IF vst%=5 THEN PROCv_chset(c%):ENDPROC
 2852 IF vst%=6 THEN PROCv_hash(c%):ENDPROC
 2854 vst%=0
 2856 ENDPROC
 2858 :
 2860 REM A whole string, for tests and for anything that already has one.
 2862 DEF PROCv_writes(s$)
 2864 LOCAL i%
 2866 FOR i%=1 TO LEN(s$):PROCv_write(ASC(MID$(s$,i%,1))):NEXT
 2868 ENDPROC
 2870 :
 2872 DEF PROCv_ground(c%)
 2874 IF u8n%>0 THEN PROCv_cont(c%):ENDPROC
 2876 IF c%<32 THEN PROCv_c0(c%):ENDPROC
 2878 IF c%=127 THEN ENDPROC
 2880 IF c%<128 THEN PROCv_glyph(FNv_map(c%)):ENDPROC
 2882 PROCv_lead(c%)
 2884 ENDPROC
 2886 :
 2888 REM ---- UTF-8 ------------------------------------------------------
 2890 REM Decoded to a codepoint here and mapped to a font slot in FNv_uni.
 2892 REM A malformed sequence emits the replacement glyph and REPROCESSES
 2894 REM the byte that broke it, so a truncated character costs one glyph
 2896 REM rather than swallowing the escape sequence that followed it.
 2898 DEF PROCv_lead(c%)
 2900 IF c%>=192 AND c%<224 THEN u8v%=c% AND 31:u8n%=1:ENDPROC
 2902 IF c%>=224 AND c%<240 THEN u8v%=c% AND 15:u8n%=2:ENDPROC
 2904 IF c%>=240 AND c%<248 THEN u8v%=c% AND 7:u8n%=3:ENDPROC
 2906 PROCv_glyph(vrep%)
 2908 ENDPROC
 2910 :
 2912 DEF PROCv_cont(c%)
 2914 IF c%<128 OR c%>191 THEN u8n%=0:PROCv_glyph(vrep%):PROCv_write(c%):ENDPROC
 2916 u8v%=u8v%*64+(c% AND 63)
 2918 u8n%=u8n%-1
 2920 IF u8n%=0 THEN PROCv_glyph(FNv_uni(u8v%))
 2922 ENDPROC
 2924 :
 2926 REM The glyph map. Phase 2b maps what the line drawing set already
 2928 REM has a shape for, so a UTF-8 box and an ESC ( 0 box are the same
 2930 REM pixels. Everything else is the replacement glyph, and the set is
 2932 REM ours to extend because we own the table - VDU 23 is not the
 2934 REM mechanism any more.
 2936 DEF FNv_uni(u%)
 2938 IF u%<128 THEN =u%
 2940 IF u%=&2500 THEN =&80+&12
 2942 IF u%=&2502 THEN =&80+&19
 2944 IF u%=&250C THEN =&80+&0D
 2946 IF u%=&2510 THEN =&80+&0C
 2948 IF u%=&2514 THEN =&80+&0E
 2950 IF u%=&2518 THEN =&80+&0B
 2952 IF u%=&251C THEN =&80+&15
 2954 IF u%=&2524 THEN =&80+&16
 2956 IF u%=&252C THEN =&80+&18
 2958 IF u%=&2534 THEN =&80+&17
 2960 IF u%=&253C THEN =&80+&0F
 2962 IF u%=&2592 THEN =&80+&02
 2964 IF u%=&25C6 THEN =&80+&01
 2966 IF u%=&00B0 THEN =&80+&07
 2968 IF u%=&00B1 THEN =&80+&08
 2970 IF u%=&00A3 THEN =&80+&1E
 2972 IF u%=&03C0 THEN =&80+&1C
 2974 IF u%=&2264 THEN =&80+&1A
 2976 IF u%=&2265 THEN =&80+&1B
 2978 IF u%=&2260 THEN =&80+&1D
 2980 IF u%=&00B7 THEN =&80+&1F
 2982 =FNv_uni2(u%)
 2984 :
 2986 REM ---- C0 ---------------------------------------------------------
 2988 DEF PROCv_c0(c%)
 2990 IF c%=8 THEN PROCv_bs:ENDPROC
 2992 IF c%=9 THEN PROCv_tab:ENDPROC
 2994 IF c%>=10 AND c%<=12 THEN pw%=FALSE:PROCv_ind:ENDPROC
 2996 IF c%=13 THEN cx%=0:pw%=FALSE:ENDPROC
 2998 IF c%=14 THEN gl%=1:ENDPROC
 3000 IF c%=15 THEN gl%=0:ENDPROC
 3002 IF c%=27 THEN vst%=1:ENDPROC
 3004 ENDPROC
 3006 :
 3008 DEF PROCv_bs
 3010 pw%=FALSE
 3012 IF cx%>0 THEN cx%=cx%-1
 3014 ENDPROC
 3016 :
 3018 REM Real tab stops, not a column count. TBC clears one or all of
 3020 REM them and a program that sets its own gets them.
 3022 DEF PROCv_tabinit
 3024 LOCAL i%
 3026 FOR i%=0 TO cols%-1:tab%?i%=0:NEXT
 3028 FOR i%=8 TO cols%-1 STEP 8:tab%?i%=1:NEXT
 3030 ENDPROC
 3032 :
 3034 DEF PROCv_tab
 3036 LOCAL i%,f%
 3038 pw%=FALSE
 3040 IF cx%>=cols%-1 THEN cx%=cols%-1:ENDPROC
 3042 f%=0:i%=cx%+1
 3044 REPEAT
 3046   IF tab%?i%<>0 THEN f%=i%
 3048   i%=i%+1
 3050 UNTIL f%<>0 OR i%>cols%-1
 3052 IF f%=0 THEN f%=cols%-1
 3054 cx%=f%
 3056 ENDPROC
 3058 :
 3060 DEF PROCv_btab
 3062 LOCAL i%,f%
 3064 pw%=FALSE
 3066 IF cx%<1 THEN cx%=0:ENDPROC
 3068 f%=-1:i%=cx%-1
 3070 REPEAT
 3072   IF tab%?i%<>0 THEN f%=i%
 3074   i%=i%-1
 3076 UNTIL f%>=0 OR i%<0
 3078 IF f%<0 THEN f%=0
 3080 cx%=f%
 3082 ENDPROC
 3084 :
 3086 DEF PROCv_tabclr(m%)
 3088 LOCAL i%
 3090 IF m%=3 THEN FOR i%=0 TO cols%-1:tab%?i%=0:NEXT
 3092 IF m%=3 THEN ENDPROC
 3094 tab%?cx%=0
 3096 ENDPROC
 3098 :
 3100 REM ---- putting a glyph down ---------------------------------------
 3102 REM The pending wrap, in three lines. A glyph written into the last
 3104 REM column does NOT move the cursor - it sets pw%, and the wrap only
 3106 REM happens when the NEXT glyph arrives. So a line that exactly fills
 3108 REM the screen leaves the cursor visible on it, a CR or a cursor move
 3110 REM cancels the wrap, and nothing has to swallow a following LF.
 3112 REM The cell is written here rather than through PROCv_put. This runs
 3114 REM once per CHARACTER of the stream, and a BBC BASIC procedure call
 3116 REM with six arguments costs seven times a bare one - measured on the
 3118 REM emulated ARM at 0.55ms against 0.08ms, which was the whole cost of
 3120 REM plain text. PROCv_put stays for callers that are not on this path.
 3122 DEF PROCv_glyph(g%)
 3124 LOCAL a%
 3126 REM Bounds checked, and the cost is affordable: phase 4 measured the
 3128 REM parser at 124,868 bytes/sec against a 3,082 bytes/sec socket, so
 3130 REM there is forty times the headroom for one comparison per character.
 3132 REM Unguarded, a cx% or cy% the parser failed to clamp writes past the
 3134 REM end of scr% into BASIC's heap - which is how a stray index becomes
 3136 REM "Bad program" or a dead machine three procedures later instead of
 3138 REM a wrong character on the screen.
 3140 IF cx%<0 OR cy%<0 OR cx%>=cols% OR cy%>=rows% THEN ENDPROC
 3142 IF pw% THEN cx%=0:PROCv_ind:pw%=FALSE
 3144 IF ins% THEN PROCv_ich(1)
 3146 a%=scr%+(cy%*cols%+cx%)*4
 3148 a%?0=g% AND 255
 3150 a%?1=((g% DIV 256) AND 15) OR (sfl%*16)
 3152 a%?2=sf%
 3154 a%?3=sb%
 3156 IF cx%<cols%-1 THEN cx%=cx%+1:ENDPROC
 3158 IF awm% THEN pw%=TRUE
 3160 ENDPROC
 3162 :
 3164 REM ESC ( 0 puts the DEC special graphics set into G0, SO and SI pick
 3166 REM between G0 and G1, and 5F-7E is the range it redefines.
 3168 DEF FNv_lin
 3170 IF gl%=0 THEN =(g0%=1)
 3172 =(g1%=1)
 3174 :
 3176 DEF FNv_map(c%)
 3178 IF c%<&5F OR c%>&7E THEN =c%
 3180 IF NOT FNv_lin THEN =c%
 3182 =128+c%-&5F
 3184 :
 3186 REM ---- ESC --------------------------------------------------------
 3188 DEF PROCv_esc(c%)
 3190 vst%=0
 3192 IF c%=91 THEN PROCv_csibegin:ENDPROC
 3194 IF c%=93 THEN vst%=3:oscp%=0:ENDPROC
 3196 IF c%=80 OR c%=88 OR c%=94 OR c%=95 THEN vst%=4:oscp%=0:ENDPROC
 3198 IF c%=40 OR c%=41 THEN vst%=5:vchs%=c%:ENDPROC
 3200 IF c%=35 THEN vst%=6:ENDPROC
 3202 IF c%=55 THEN PROCv_sc:ENDPROC
 3204 IF c%=56 THEN PROCv_rc:ENDPROC
 3206 IF c%=68 THEN pw%=FALSE:PROCv_ind:ENDPROC
 3208 IF c%=69 THEN cx%=0:pw%=FALSE:PROCv_ind:ENDPROC
 3210 IF c%=77 THEN pw%=FALSE:PROCv_ri:ENDPROC
 3212 IF c%=72 THEN tab%?cx%=1:ENDPROC
 3214 IF c%=99 THEN PROCv_reset:ENDPROC
 3216 ENDPROC
 3218 :
 3220 DEF PROCv_chset(c%)
 3222 vst%=0
 3224 IF vchs%=40 THEN g0%=0
 3226 IF vchs%=41 THEN g1%=0
 3228 IF c%<>48 THEN ENDPROC
 3230 IF vchs%=40 THEN g0%=1
 3232 IF vchs%=41 THEN g1%=1
 3234 ENDPROC
 3236 :
 3238 REM ESC # 8, the DEC alignment pattern. A screenful of E, and the one
 3240 REM sequence whose whole purpose is to be looked at.
 3242 DEF PROCv_hash(c%)
 3244 LOCAL x%,y%
 3246 vst%=0
 3248 IF c%<>56 THEN ENDPROC
 3250 FOR y%=0 TO rows%-1
 3252   FOR x%=0 TO cols%-1:PROCv_put(x%,y%,69,sf%,sb%,0):NEXT
 3254 NEXT
 3256 cx%=0:cy%=0:pw%=FALSE
 3258 ENDPROC
 3260 :
 3262 REM OSC and the other string sequences are consumed and dropped -
 3264 REM window titles and shell integration markers. They end at BEL or
 3266 REM at ST, and ST is ESC followed by anything, which is close enough
 3268 REM to keep a title out of the cell model.
 3270 DEF PROCv_osc(c%)
 3272 IF c%=7 THEN vst%=0:oscp%=0:ENDPROC
 3274 IF oscp%=1 THEN vst%=0:oscp%=0:ENDPROC
 3276 IF c%=27 THEN oscp%=1
 3278 ENDPROC
 3280 :
 3282 DEF PROCv_str(c%)
 3284 IF c%=7 THEN vst%=0:oscp%=0:ENDPROC
 3286 IF oscp%=1 THEN vst%=0:oscp%=0:ENDPROC
 3288 IF c%=27 THEN oscp%=1
 3290 ENDPROC
 3292 :
 3294 REM ---- CSI --------------------------------------------------------
 3296 REM -1 means absent, which is not the same as zero: CUP with no
 3298 REM parameters is row 1 column 1, CUP with a 0 is also row 1, but ED
 3300 REM with no parameter is 0 and ED with a 2 is not.
 3302 DEF PROCv_csibegin
 3304 LOCAL i%
 3306 np%=0:prv%=0:vint%=0
 3308 FOR i%=0 TO 15:par%!(i%*4)=-1:NEXT
 3310 vst%=2
 3312 ENDPROC
 3314 :
 3316 DEF PROCv_csi(c%)
 3318 IF c%>=48 AND c%<=57 THEN PROCv_param(c%):ENDPROC
 3320 IF c%=59 OR c%=58 THEN PROCv_nextp:ENDPROC
 3322 IF c%>=60 AND c%<=63 THEN prv%=c%:ENDPROC
 3324 IF c%>=32 AND c%<=47 THEN vint%=c%:ENDPROC
 3326 IF c%>=64 AND c%<=126 THEN vst%=0:PROCv_do(c%):ENDPROC
 3328 IF c%<32 THEN PROCv_c0(c%):ENDPROC
 3330 vst%=0
 3332 ENDPROC
 3334 :
 3336 REM Saturating, because a parameter is an arbitrary run of digits from
 3338 REM the far end and nothing stops it being longer than a 32-bit signed
 3340 REM integer. Unclamped this raised "Number too big" in a live session -
 3342 REM error 20 at this line - and took the whole terminal down with it.
 3344 REM
 3346 REM 65535 is far past anything meaningful: the largest parameter this
 3348 REM engine can use is a mode number like 2004, and the largest that
 3350 REM addresses the screen is 80. Saturating rather than wrapping matters
 3352 REM because a wrapped value is a PLAUSIBLE small number, and a cursor
 3354 REM move to a plausible wrong place is harder to see than one clamped
 3356 REM to the edge.
 3358 DEF PROCv_param(c%)
 3360 LOCAL v%
 3362 v%=par%!(np%*4)
 3364 IF v%<0 THEN v%=0
 3366 IF v%>6553 THEN par%!(np%*4)=65535:ENDPROC
 3368 v%=v%*10+(c%-48)
 3370 IF v%>65535 THEN v%=65535
 3372 par%!(np%*4)=v%
 3374 ENDPROC
 3376 :
 3378 DEF PROCv_nextp
 3380 IF np%<15 THEN np%=np%+1
 3382 ENDPROC
 3384 :
 3386 DEF FNv_p(i%,d%)
 3388 IF i%>15 THEN =d%
 3390 IF par%!(i%*4)<0 THEN =d%
 3392 =par%!(i%*4)
 3394 :
 3396 DEF FNv_p1(i%)
 3398 LOCAL v%
 3400 v%=FNv_p(i%,1)
 3402 IF v%<1 THEN v%=1
 3404 =v%
 3406 :
 3408 REM The dispatch. Long, flat and in ASCII order of the final byte,
 3410 REM because a native core will write it as a switch and the order is
 3412 REM the only documentation a switch has.
 3414 DEF PROCv_do(c%)
 3416 IF prv%<>0 THEN PROCv_priv(c%):ENDPROC
 3418 IF c%=64 THEN PROCv_ich(FNv_p1(0)):ENDPROC
 3420 IF c%=65 THEN PROCv_cuu(FNv_p1(0)):ENDPROC
 3422 IF c%=66 THEN PROCv_cud(FNv_p1(0)):ENDPROC
 3424 IF c%=67 THEN PROCv_cuf(FNv_p1(0)):ENDPROC
 3426 IF c%=68 THEN PROCv_cub(FNv_p1(0)):ENDPROC
 3428 IF c%=69 THEN cx%=0:PROCv_cud(FNv_p1(0)):ENDPROC
 3430 IF c%=70 THEN cx%=0:PROCv_cuu(FNv_p1(0)):ENDPROC
 3432 IF c%=71 OR c%=96 THEN PROCv_col(FNv_p1(0)-1):ENDPROC
 3434 IF c%=72 OR c%=102 THEN PROCv_cup(FNv_p1(0)-1,FNv_p1(1)-1):ENDPROC
 3436 IF c%=73 THEN PROCv_ctab(FNv_p1(0)):ENDPROC
 3438 IF c%=74 THEN PROCv_ed(FNv_p(0,0)):ENDPROC
 3440 IF c%=75 THEN PROCv_el(FNv_p(0,0)):ENDPROC
 3442 IF c%=76 THEN PROCv_il(FNv_p1(0)):ENDPROC
 3444 IF c%=77 THEN PROCv_dl(FNv_p1(0)):ENDPROC
 3446 IF c%=80 THEN PROCv_dch(FNv_p1(0)):ENDPROC
 3448 IF c%=83 THEN PROCv_su(FNv_p1(0)):ENDPROC
 3450 IF c%=84 THEN PROCv_sd(FNv_p1(0)):ENDPROC
 3452 IF c%=88 THEN PROCv_ech(FNv_p1(0)):ENDPROC
 3454 IF c%=90 THEN PROCv_cbt(FNv_p1(0)):ENDPROC
 3456 IF c%=99 THEN PROCv_da:ENDPROC
 3458 IF c%=100 THEN PROCv_row(FNv_p1(0)-1):ENDPROC
 3460 IF c%=103 THEN PROCv_tabclr(FNv_p(0,0)):ENDPROC
 3462 IF c%=104 THEN PROCv_sm(TRUE):ENDPROC
 3464 IF c%=108 THEN PROCv_sm(FALSE):ENDPROC
 3466 IF c%=109 THEN PROCv_sgr:ENDPROC
 3468 IF c%=110 THEN PROCv_dsr:ENDPROC
 3470 IF c%=114 THEN PROCv_stbm:ENDPROC
 3472 IF c%=115 THEN PROCv_sc:ENDPROC
 3474 IF c%=117 THEN PROCv_rc:ENDPROC
 3476 ENDPROC
 3478 :
 3480 REM ---- cursor movement --------------------------------------------
 3482 REM CUU and CUD stop at the edge of the SCROLLING REGION when the
 3484 REM cursor is inside it and at the edge of the screen when it is not,
 3486 REM and neither of them ever scrolls. Getting that wrong is how a
 3488 REM status line outside the region gets dragged into it.
 3490 DEF PROCv_cuu(n%)
 3492 LOCAL l%
 3494 pw%=FALSE
 3496 l%=0
 3498 IF cy%>=top% THEN l%=top%
 3500 cy%=cy%-n%
 3502 IF cy%<l% THEN cy%=l%
 3504 ENDPROC
 3506 :
 3508 DEF PROCv_cud(n%)
 3510 LOCAL l%
 3512 pw%=FALSE
 3514 l%=rows%-1
 3516 IF cy%<=bot% THEN l%=bot%
 3518 cy%=cy%+n%
 3520 IF cy%>l% THEN cy%=l%
 3522 ENDPROC
 3524 :
 3526 DEF PROCv_cuf(n%)
 3528 pw%=FALSE
 3530 cx%=cx%+n%
 3532 IF cx%>cols%-1 THEN cx%=cols%-1
 3534 ENDPROC
 3536 :
 3538 DEF PROCv_cub(n%)
 3540 pw%=FALSE
 3542 cx%=cx%-n%
 3544 IF cx%<0 THEN cx%=0
 3546 ENDPROC
 3548 :
 3550 DEF PROCv_col(x%)
 3552 pw%=FALSE
 3554 cx%=x%
 3556 IF cx%<0 THEN cx%=0
 3558 IF cx%>cols%-1 THEN cx%=cols%-1
 3560 ENDPROC
 3562 :
 3564 DEF PROCv_row(y%)
 3566 PROCv_cup(y%,cx%)
 3568 ENDPROC
 3570 :
 3572 REM Origin mode makes row 1 the top of the region rather than the top
 3574 REM of the screen, and confines the cursor to it.
 3576 DEF PROCv_cup(r%,c%)
 3578 pw%=FALSE
 3580 IF dom% THEN r%=r%+top%
 3582 cy%=r%:cx%=c%
 3584 IF cy%<0 THEN cy%=0
 3586 IF cx%<0 THEN cx%=0
 3588 IF cy%>rows%-1 THEN cy%=rows%-1
 3590 IF cx%>cols%-1 THEN cx%=cols%-1
 3592 IF dom% AND cy%<top% THEN cy%=top%
 3594 IF dom% AND cy%>bot% THEN cy%=bot%
 3596 ENDPROC
 3598 :
 3600 DEF PROCv_ctab(n%)
 3602 LOCAL i%
 3604 FOR i%=1 TO n%:PROCv_tab:NEXT
 3606 ENDPROC
 3608 :
 3610 DEF PROCv_cbt(n%)
 3612 LOCAL i%
 3614 FOR i%=1 TO n%:PROCv_btab:NEXT
 3616 ENDPROC
 3618 :
 3620 REM DECSTBM. Homes the cursor, which is the part programs rely on and
 3622 REM the part that is easy to leave out.
 3624 DEF PROCv_stbm
 3626 PROCv_region(FNv_p1(0)-1,FNv_p(1,rows%)-1)
 3628 cx%=0:cy%=0
 3630 IF dom% THEN cy%=top%
 3632 pw%=FALSE
 3634 ENDPROC
 3636 :
 3638 DEF PROCv_sc
 3640 sv_x%=cx%:sv_y%=cy%:sv_f%=sf%:sv_b%=sb%:sv_l%=sfl%:sv_g%=g0%
 3642 ENDPROC
 3644 :
 3646 DEF PROCv_rc
 3648 cx%=sv_x%:cy%=sv_y%:sf%=sv_f%:sb%=sv_b%:sfl%=sv_l%:g0%=sv_g%
 3650 IF cx%>cols%-1 THEN cx%=cols%-1
 3652 IF cy%>rows%-1 THEN cy%=rows%-1
 3654 pw%=FALSE
 3656 ENDPROC
 3658 :
 3660 DEF PROCv_reset
 3662 sf%=7:sb%=0:sfl%=0
 3664 PROCv_region(0,rows%-1)
 3666 cx%=0:cy%=0:pw%=FALSE
 3668 awm%=TRUE:dom%=FALSE:ins%=FALSE:cvis%=TRUE:ckm%=FALSE:bp%=FALSE
 3670 g0%=0:g1%=0:gl%=0
 3672 u8n%=0:alton%=FALSE
 3674 PROCv_tabinit
 3676 PROCv_fill(0,rows%-1,sf%,sb%)
 3678 ENDPROC
 3680 :
 3682 REM ---- modes ------------------------------------------------------
 3684 DEF PROCv_sm(on%)
 3686 LOCAL i%,v%
 3688 i%=0
 3690 REPEAT
 3692   v%=FNv_p(i%,0)
 3694   IF v%=4 THEN ins%=on%
 3696   i%=i%+1
 3698 UNTIL i%>np%
 3700 ENDPROC
 3702 :
 3704 DEF PROCv_priv(c%)
 3706 LOCAL i%,on%
 3708 IF prv%<>63 THEN ENDPROC
 3710 IF c%<>104 AND c%<>108 THEN ENDPROC
 3712 on%=(c%=104)
 3714 i%=0
 3716 REPEAT
 3718   PROCv_dec(FNv_p(i%,0),on%)
 3720   i%=i%+1
 3722 UNTIL i%>np%
 3724 ENDPROC
 3726 :
 3728 REM Each of these is written flat. ELSE binds to the first IF on the
 3730 REM line in BBC BASIC, so IF v%=1048 THEN IF on% THEN A ELSE B runs B
 3732 REM for every mode that is NOT 1048.
 3734 DEF PROCv_dec(v%,on%)
 3736 IF v%=1 THEN ckm%=on%:ENDPROC
 3738 IF v%=6 THEN PROCv_setom(on%):ENDPROC
 3740 IF v%=7 THEN awm%=on%:ENDPROC
 3742 IF v%=25 THEN cvis%=on%:ENDPROC
 3744 IF v%=47 OR v%=1047 OR v%=1049 THEN PROCv_alt(v%,on%):ENDPROC
 3746 IF v%=1048 AND on% THEN PROCv_sc
 3748 IF v%=1048 AND NOT on% THEN PROCv_rc
 3750 IF v%=2004 THEN bp%=on%:ENDPROC
 3752 ENDPROC
 3754 :
 3756 DEF PROCv_setom(on%)
 3758 dom%=on%
 3760 cx%=0:cy%=0
 3762 IF dom% THEN cy%=top%
 3764 pw%=FALSE
 3766 ENDPROC
 3768 :
 3770 REM The alternate screen, and a REAL second buffer. 9.3 could only
 3772 REM clear on the way in and clear again on the way out, so anything
 3774 REM behind a full-screen program was lost; here it comes back.
 3776 REM
 3778 REM The buffer is DIMmed the first time something asks for it, so a
 3780 REM replay that never switches screens does not pay 20K for it.
 3782 DEF PROCv_alt(v%,on%)
 3784 IF alt%=0 THEN DIM alt% cols%*rows%*4-1
 3786 IF on% AND alton% THEN ENDPROC
 3788 IF NOT on% AND NOT alton% THEN ENDPROC
 3790 IF on% THEN PROCv_altin(v%):ENDPROC
 3792 PROCv_altout(v%)
 3794 ENDPROC
 3796 :
 3798 DEF PROCv_altin(v%)
 3800 LOCAL i%
 3802 IF v%=1049 THEN PROCv_sc
 3804 FOR i%=0 TO (cols%*rows%-1)*4 STEP 4:alt%!i%=scr%!i%:NEXT
 3806 IF v%<>47 THEN PROCv_fill(0,rows%-1,sf%,sb%)
 3808 IF v%<>47 THEN cx%=0:cy%=0
 3810 alton%=TRUE
 3812 pw%=FALSE
 3814 ENDPROC
 3816 :
 3818 DEF PROCv_altout(v%)
 3820 LOCAL i%
 3822 FOR i%=0 TO (cols%*rows%-1)*4 STEP 4:scr%!i%=alt%!i%:NEXT
 3824 alton%=FALSE
 3826 IF v%=1049 THEN PROCv_rc
 3828 pw%=FALSE
 3830 ENDPROC
 3832 :
 3834 REM ---- SGR --------------------------------------------------------
 3836 DEF PROCv_sgr
 3838 LOCAL i%,v%
 3840 IF np%=0 AND par%!0<0 THEN PROCv_sgr0:ENDPROC
 3842 i%=0
 3844 REPEAT
 3846   v%=FNv_p(i%,0)
 3848   IF v%=38 OR v%=48 THEN i%=FNv_ext(i%,v%) ELSE PROCv_sgr1(v%)
 3850   i%=i%+1
 3852 UNTIL i%>np%
 3854 ENDPROC
 3856 :
 3858 DEF PROCv_sgr0
 3860 sf%=7:sb%=0:sfl%=0
 3862 ENDPROC
 3864 :
 3866 REM 2 faint and 3 italic are parsed and dropped: an 8x8 cell has
 3868 REM nowhere to put them and a wrong rendering is worse than none.
 3870 DEF PROCv_sgr1(v%)
 3872 IF v%=0 THEN PROCv_sgr0:ENDPROC
 3874 IF v%=1 THEN sfl%=sfl% OR 4:ENDPROC
 3876 IF v%=4 THEN sfl%=sfl% OR 2:ENDPROC
 3878 IF v%=7 THEN sfl%=sfl% OR 1:ENDPROC
 3880 IF v%=9 THEN sfl%=sfl% OR 8:ENDPROC
 3882 IF v%=21 OR v%=22 THEN sfl%=sfl% AND 11:ENDPROC
 3884 IF v%=24 THEN sfl%=sfl% AND 13:ENDPROC
 3886 IF v%=27 THEN sfl%=sfl% AND 14:ENDPROC
 3888 IF v%=29 THEN sfl%=sfl% AND 7:ENDPROC
 3890 IF v%>=30 AND v%<=37 THEN sf%=v%-30:ENDPROC
 3892 IF v%=39 THEN sf%=7:ENDPROC
 3894 IF v%>=40 AND v%<=47 THEN sb%=v%-40:ENDPROC
 3896 IF v%=49 THEN sb%=0:ENDPROC
 3898 IF v%>=90 AND v%<=97 THEN sf%=v%-82:ENDPROC
 3900 IF v%>=100 AND v%<=107 THEN sb%=v%-92:ENDPROC
 3902 ENDPROC
 3904 :
 3906 REM 38;5;n and 48;5;n land on the palette exactly - fbpal2 proved all
 3908 REM 256 entries are programmable, so nothing is approximated. Only
 3910 REM 38;2;r;g;b has to be reduced, and it is reduced to the same cube
 3912 REM the palette was built from rather than to sixteen colours.
 3914 DEF FNv_ext(i%,w%)
 3916 LOCAL m%,c%
 3918 m%=FNv_p(i%+1,0)
 3920 IF m%=5 THEN PROCv_ink2(w%,FNv_p(i%+2,0)):=i%+2
 3922 IF m%<>2 THEN =i%+1
 3924 c%=FNv_rgb(FNv_p(i%+2,0),FNv_p(i%+3,0),FNv_p(i%+4,0))
 3926 PROCv_ink2(w%,c%)
 3928 =i%+4
 3930 :
 3932 DEF PROCv_ink2(w%,c%)
 3934 IF c%<0 OR c%>255 THEN ENDPROC
 3936 IF w%=38 THEN sf%=c%:ENDPROC
 3938 sb%=c%
 3940 ENDPROC
 3942 :
 3944 DEF FNv_rgb(r%,g%,b%)
 3946 IF r%=g% AND g%=b% THEN =FNv_grey(r%)
 3948 =16+FNv_lev(r%)*36+FNv_lev(g%)*6+FNv_lev(b%)
 3950 :
 3952 DEF FNv_lev(v%)
 3954 IF v%<48 THEN =0
 3956 IF v%<115 THEN =1
 3958 =(v%-35) DIV 40
 3960 :
 3962 DEF FNv_grey(v%)
 3964 IF v%<8 THEN =16
 3966 IF v%>238 THEN =231
 3968 =232+(v%-8) DIV 10
 3970 :
 3972 REM ---- the reply channel ------------------------------------------
 3974 REM Nothing on the BBC side could answer a cursor position report
 3976 REM before. FNv_reply hands the bytes to the client, which owns the
 3978 REM socket, and clears them by being read.
 3980 DEF PROCv_say(s$)
 3982 rep$=rep$+s$
 3984 ENDPROC
 3986 :
 3988 DEF FNv_reply
 3990 LOCAL s$
 3992 s$=rep$
 3994 rep$=""
 3996 =s$
 3998 :
 4000 DEF PROCv_dsr
 4002 LOCAL n%,r%
 4004 n%=FNv_p(0,0)
 4006 IF n%=5 THEN PROCv_say(CHR$(27)+"[0n"):ENDPROC
 4008 IF n%<>6 THEN ENDPROC
 4010 r%=cy%
 4012 IF dom% THEN r%=cy%-top%
 4014 PROCv_say(CHR$(27)+"["+STR$(r%+1)+";"+STR$(cx%+1)+"R")
 4016 ENDPROC
 4018 :
 4020 REM VT102: no printer, no selective erase, and the one thing here we
 4022 REM are honestly not is an xterm. A bbcvt terminfo entry is phase 6.
 4024 DEF PROCv_da
 4026 IF FNv_p(0,0)<>0 THEN ENDPROC
 4028 PROCv_say(CHR$(27)+"[?6c")
 4030 ENDPROC
 4032 :
 4034 REM What the keyboard layer has to ask: cursor keys per DECCKM, and
 4036 REM whether the far end asked for its pastes to be bracketed.
 4038 DEF FNv_mode(n%)
 4040 IF n%=1 THEN =ckm%
 4042 IF n%=4 THEN =ins%
 4044 IF n%=6 THEN =dom%
 4046 IF n%=7 THEN =awm%
 4048 IF n%=25 THEN =cvis%
 4050 IF n%=1049 THEN =alton%
 4052 IF n%=2004 THEN =bp%
 4054 =FALSE
 4056 :
 4058 REM ---- the DEC special graphics bitmaps ---------------------------
 4060 REM 5F to 7E, eight rows each, bit 7 leftmost. The control pictures
 4062 REM at 62-65, 68 and 69 are deliberately blank: they exist to be
 4064 REM shown in a debugging mode nobody runs, and a wrong shape in a box
 4066 REM is worse than a space.
 4068 :
 4070 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 5F blank
 4072 DATA &00,&18,&3C,&7E,&3C,&18,&00,&00  :REM 60 diamond
 4074 DATA &55,&AA,&55,&AA,&55,&AA,&55,&AA  :REM 61 chequer
 4076 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 62 HT
 4078 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 63 FF
 4080 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 64 CR
 4082 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 65 LF
 4084 DATA &00,&38,&28,&38,&00,&00,&00,&00  :REM 66 degree
 4086 DATA &00,&18,&18,&7E,&18,&18,&7E,&00  :REM 67 plus minus
 4088 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 68 NL
 4090 DATA &00,&00,&00,&00,&00,&00,&00,&00  :REM 69 VT
 4092 DATA &18,&18,&18,&F8,&00,&00,&00,&00  :REM 6A bottom right
 4094 DATA &00,&00,&00,&F8,&18,&18,&18,&18  :REM 6B top right
 4096 DATA &00,&00,&00,&1F,&18,&18,&18,&18  :REM 6C top left
 4098 DATA &18,&18,&18,&1F,&00,&00,&00,&00  :REM 6D bottom left
 4100 DATA &18,&18,&18,&FF,&18,&18,&18,&18  :REM 6E cross
 4102 DATA &FF,&00,&00,&00,&00,&00,&00,&00  :REM 6F scan 1
 4104 DATA &00,&FF,&00,&00,&00,&00,&00,&00  :REM 70 scan 3
 4106 DATA &00,&00,&00,&FF,&00,&00,&00,&00  :REM 71 scan 5
 4108 DATA &00,&00,&00,&00,&00,&FF,&00,&00  :REM 72 scan 7
 4110 DATA &00,&00,&00,&00,&00,&00,&00,&FF  :REM 73 scan 9
 4112 DATA &18,&18,&18,&1F,&18,&18,&18,&18  :REM 74 tee right
 4114 DATA &18,&18,&18,&F8,&18,&18,&18,&18  :REM 75 tee left
 4116 DATA &18,&18,&18,&FF,&00,&00,&00,&00  :REM 76 tee up
 4118 DATA &00,&00,&00,&FF,&18,&18,&18,&18  :REM 77 tee down
 4120 DATA &18,&18,&18,&18,&18,&18,&18,&18  :REM 78 vertical
 4122 DATA &0C,&18,&30,&18,&0C,&00,&7E,&00  :REM 79 less equal
 4124 DATA &30,&18,&0C,&18,&30,&00,&7E,&00  :REM 7A more equal
 4126 DATA &00,&00,&7E,&24,&24,&24,&24,&00  :REM 7B pi
 4128 DATA &04,&08,&7E,&10,&7E,&20,&40,&00  :REM 7C not equal
 4130 DATA &1C,&22,&20,&78,&20,&20,&7E,&00  :REM 7D sterling
 4132 DATA &00,&00,&00,&18,&18,&00,&00,&00  :REM 7E middle dot
 4134 REM ---- clearing the rows a scroll exposes -----------------------
 4136 REM
 4138 REM PROCv_fill above fills the MODEL for the rows the scroll exposed
 4140 REM and marks them dirty, but the glass move only shifts pixels UP -
 4142 REM it never clears what it uncovers. So the bottom row keeps its old
 4144 REM pixels, and the NEXT scroll carries those up too. With drain%=1024
 4146 REM the pump scrolls many times before it flushes once, and the result
 4148 REM is a trail of stale characters marching up the screen until the
 4150 REM flush corrects it. The final state was always right - the glass
 4152 REM check reports 0 stale cells - so this is tearing, not corruption.
 4154 REM
 4156 REM Clearing what the move exposed is also what real hardware does: a
 4158 REM blank line appears at the bottom and text is drawn into it.
 4160 REM
 4162 REM Cost matters, because the point of the recent work was to make
 4164 REM scrolling FASTER. A word-fill in BASIC is 1,280 iterations for one
 4166 REM text row, about 12% on top of a 1.67cs scroll. Copying a
 4168 REM pre-cleared row with the assembled move is 5,120 bytes at the
 4170 REM ~19 MB/sec the framebuffer manages: nearer 1.6%. The blank row is
 4172 REM rebuilt only when the background colour changes, which in a
 4174 REM terminal is almost never.
 4176 DEF PROCv_clrg(t%,b%,f%,bg%)
 4178 LOCAL i%,w%,d%,n%
 4180 IF NOT glass% THEN ENDPROC
 4182 IF t%>b% OR fb%=0 THEN ENDPROC
 4184 IF blkr%=0 THEN DIM blkr% ch%*pit%-1
 4186 IF blkc%<>bg% THEN PROCv_mkblank(bg%)
 4188 REM THE SHADOW MUST FOLLOW. This writes the glass outside the flush,
 4190 REM so leaving the shadow describing the OLD content breaks the one
 4192 REM invariant the engine rests on. After a scroll the shadow still
 4194 REM held the PREVIOUS row, and where the next row was identical -
 4196 REM "drwxrwxr-x" at 0-9, "user user" at 14-22 in an ll listing -
 4198 REM model matched shadow, the flush skipped those cells and the glass
 4200 REM stayed blank, while filenames differed and so painted. Set the
 4202 REM shadow to what the glass NOW holds.
 4204 PROCv_clrs(t%,b%,f%,bg%):IF fastmv% THEN PROCv_clrf(t%,b%):ENDPROC
 4206 w%=!blkr%
 4208 d%=fb%+t%*ch%*pit%
 4210 n%=(b%-t%+1)*ch%*pit%
 4212 FOR i%=0 TO n%-4 STEP 4:d%!i%=w%:NEXT
 4214 ENDPROC
 4216 :
 4218 REM ch%*pit% is 5,120 here, a multiple of 64, so the assembled move
 4220 REM takes it without needing its byte tail.
 4222 DEF PROCv_clrf(t%,b%)
 4224 LOCAL i%
 4226 FOR i%=t% TO b%:PROCv_mv(fb%+i%*ch%*pit%,blkr%,ch%*pit%):NEXT
 4228 ENDPROC
 4230 :
 4232 DEF PROCv_mkblank(bg%)
 4234 LOCAL i%,w%,n%
 4236 FOR i%=0 TO 3:xp%?i%=bg%:NEXT
 4238 w%=!xp%
 4240 n%=ch%*pit%
 4242 FOR i%=0 TO n%-4 STEP 4:blkr%!i%=w%:NEXT
 4244 blkc%=bg%
 4246 REM xp% IS THE BLITTER'S INK TABLE, borrowed here as scratch - and
 4248 REM PROCv_ink caches on cf%/cb%, so it will NOT rebuild a table this
 4250 REM has just trashed. Without these two the blitter paints the first
 4252 REM nibble's pixels in the BACKGROUND colour: the cells are painted,
 4254 REM invisibly, stale_ops reads 1, they decode as spaces, and a forced
 4256 REM repaint fixes them. PROCv_wipe does exactly this at 1588 for the
 4258 REM same reason; this was added without copying it.
 4260 cf%=-1:cb%=-1
 4262 ENDPROC
 4264 :
 4266 REM One shadow word per cleared cell: glyph 32, NO FLAGS, and the
 4268 REM same fg/bg PROCv_fill just wrote to the model - so a plain blank
 4270 REM cell matches and the flush skips it. That is 80 cells a scroll it
 4272 REM no longer paints over glass that is already blank: a quarter of
 4274 REM all painting in an htop run. Flags stay 0 deliberately, because a
 4276 REM blank carrying underline or reverse DOES draw pixels, and must
 4278 REM mismatch so the flush paints it.
 4280 DEF PROCv_clrs(t%,b%,f%,bg%)
 4282 LOCAL a%,e%
 4284 a%=shd%+t%*cols%*4
 4286 e%=shd%+(b%+1)*cols%*4
 4288 REPEAT
 4290   a%?0=32:a%?1=0:a%?2=f%:a%?3=bg%
 4292   a%=a%+4
 4294 UNTIL a%>=e%
 4296 ENDPROC
 4298 REM ================ glyphs no BBC font carries ================
 4300 REM
 4302 REM Measured from captures/, not guessed. btop asks for 19 characters this
 4304 REM font has never had, 1,569 times across them, and two of those - U+25A0
 4306 REM and U+2591 - are 1,394 of the total. Until now every one of them came
 4308 REM out as the replacement glyph.
 4310 REM
 4312 REM 0-255 is the harvested driver font, 256 up is this, 512 up is braille.
 4314 REM The cell's glyph field is 12 bits (line 1048) and the blitter indexes
 4316 REM font% flat, so nothing else had to change to reach them.
 4318 REM
 4320 REM Bit 7 is the leftmost pixel, as line 1420 established on hardware.
 4322 DEF PROCv_extra
 4324 LOCAL c%,y%,b%
 4326 RESTORE 4456
 4328 FOR c%=0 TO 19
 4330   FOR y%=0 TO ch%-1
 4332     READ b%
 4334     font%?((256+c%)*ch%+y%)=b%
 4336   NEXT
 4338 NEXT
 4340 ENDPROC
 4342 :
 4344 REM ================ braille, generated not stored ================
 4346 REM
 4348 REM All 256 of them, because they cost almost nothing to make: a braille
 4350 REM cell IS a 2x4 bitmap and the codepoint's low byte IS the dot pattern.
 4352 REM Storing them would be 2KB of DATA for something a dozen lines compute.
 4354 REM
 4356 REM Dots 1-3 are the left column downwards and 4-6 the right, with 7 and 8
 4358 REM the later-added bottom pair - so down the cell the bits are 0,1,2,6 on
 4360 REM the left and 3,4,5,7 on the right, which is why the fourth row is the
 4362 REM odd one out below.
 4364 REM
 4366 REM Each dot fills its whole 4x2 region rather than being a round dot.
 4368 REM btop draws line graphs with these, and solid regions join into a
 4370 REM readable trace where dots would only stipple.
 4372 DEF PROCv_braille
 4374 LOCAL u%,r%,m%,lb%,rb%
 4376 FOR u%=0 TO 255
 4378   FOR r%=0 TO 3
 4380     lb%=r%:rb%=r%+3
 4382     IF r%=3 THEN lb%=6:rb%=7
 4384     m%=0
 4386     IF (u% AND (2^lb%))<>0 THEN m%=m% OR &F0
 4388     IF (u% AND (2^rb%))<>0 THEN m%=m% OR &0F
 4390     font%?((512+u%)*ch%+r%*2)=m%
 4392     font%?((512+u%)*ch%+r%*2+1)=m%
 4394   NEXT
 4396 NEXT
 4398 ENDPROC
 4400 :
 4402 REM The codepoints FNv_uni does not know. Split out because 2936-2982 is
 4404 REM packed at step 5 with no room left, and ordered by how often the
 4406 REM captures actually asked for each one.
 4408 DEF FNv_uni2(u%)
 4410 IF u%=&25A0 THEN =259
 4412 IF u%=&2591 THEN =257
 4414 IF u%=&2588 THEN =256
 4416 IF u%=&2593 THEN =258
 4418 IF u%>=&2800 AND u%<=&28FF THEN =512+(u%-&2800)
 4420 IF u%=&25B2 THEN =260
 4422 IF u%=&25BC THEN =261
 4424 IF u%=&25BD THEN =262
 4426 IF u%=&2190 THEN =263
 4428 IF u%=&2191 THEN =264
 4430 IF u%=&2192 THEN =265
 4432 IF u%=&2193 THEN =266
 4434 IF u%=&21B5 THEN =267
 4436 IF u%=&256D THEN =268
 4438 IF u%=&256E THEN =269
 4440 IF u%=&256F THEN =270
 4442 IF u%=&2570 THEN =271
 4444 IF u%=&00B9 THEN =272
 4446 IF u%=&00B2 THEN =273
 4448 IF u%=&00B3 THEN =274
 4450 IF u%=&2074 THEN =275
 4452 =FNv_uni3(u%)
 4454 :
 4456 DATA 255,255,255,255,255,255,255,255
 4458 DATA 136,0,34,0,136,0,34,0
 4460 DATA 238,187,238,187,238,187,238,187
 4462 DATA 0,126,126,126,126,126,126,0
 4464 DATA 0,24,24,60,60,126,255,0
 4466 DATA 0,255,126,60,60,24,24,0
 4468 DATA 0,255,129,195,66,102,36,24
 4470 DATA 0,16,48,127,48,16,0,0
 4472 DATA 0,24,60,126,24,24,24,0
 4474 DATA 0,8,12,254,12,8,0,0
 4476 DATA 0,24,24,24,126,60,24,0
 4478 DATA 0,2,2,34,98,254,96,32
 4480 DATA 0,0,0,15,24,24,24,24
 4482 DATA 0,0,0,240,24,24,24,24
 4484 DATA 24,24,24,240,0,0,0,0
 4486 DATA 24,24,24,15,0,0,0,0
 4488 DATA 24,56,24,24,60,0,0,0
 4490 DATA 60,102,12,24,126,0,0,0
 4492 DATA 60,102,28,102,60,0,0,0
 4494 DATA 12,28,60,108,126,12,0,0
 4496 :
 4498 REM ============ private-use icons, and the block elements ============
 4500 REM
 4502 REM Measured from the machine. The Arch logo needed nothing - it is ASCII -
 4504 REM but archbox's fastfetch config is written round Nerd Font icons, and those
 4506 REM live in Unicode's PRIVATE USE areas, where no glyph is implied at all.
 4508 REM The colour palette row is 21 of them by itself. They were rasterised
 4510 REM from the font archbox renders them with, MesloLGS Nerd Font Mono, scaled
 4512 REM into 8x8. An unmapped PRIVATE codepoint gets a neutral mark rather than
 4514 REM "?", there being nothing it ought to have been; an unmapped REAL one
 4516 REM still gets "?". docs/glyphs.md has the rest.
 4518 REM
 4520 REM Third in the chain because 2936-2982 and 4408-4452 are both full.
 4522 DEF FNv_uni3(u%)
 4524 IF u%>=&2580 AND u%<=&259F THEN =768+u%-&2580
 4526 IF (u%>=&E000 AND u%<=&F8FF) OR (u%>=&F0000 AND u%<=&FFFFD) THEN =FNv_icon(u%)
 4528 IF u%>=&1FB3C AND u%<=&1FB8B THEN =1248+u%-&1FB3C
 4529 IF u%>=&2550 AND u%<=&256C THEN =800+u%-&2550
 4530 IF nmap%=1 AND u%>=&1CD00 AND u%<=&1CDE5 THEN =832+octm%?(u%-&1CD00)
 4531 IF nmap%=1 AND u%>=&1FB00 AND u%<=&1FB3B THEN =1088+sexm%?(u%-&1FB00)
 4532 IF u%>=&A0 AND u%<=&FF THEN =1152+u%-&A0
 4533 =FNv_sym(u%)
 4534 REM Sorted by codepoint so the lookup can bisect: a linear scan would be 27
 4536 REM BASIC statements per icon, and one fastfetch draws 40 of them.
 4538 DEF PROCv_icons
 4540 LOCAL i%,y%,b%
 4542 RESTORE 4672
 4544 READ nicon%
 4546 DIM icon% nicon%*4-1
 4548 FOR i%=0 TO nicon%-1
 4550   READ b%:icon%!(i%*4)=b%
 4552   FOR y%=0 TO ch%-1:READ b%:font%?((276+i%)*ch%+y%)=b%:NEXT
 4554 NEXT
 4556 vpua%=276+nicon%
 4558 FOR y%=0 TO ch%-1:font%?(vpua%*ch%+y%)=0:NEXT
 4560 FOR y%=2 TO 5:font%?(vpua%*ch%+y%)=&3C:NEXT
 4562 ENDPROC
 4564 :
 4566 REM No early return from inside the REPEAT: leaving a loop through = leaves
 4568 REM its stack entry behind, and enough of those end the program.
 4570 DEF FNv_icon(u%)
 4572 LOCAL lo%,hi%,md%,c%,r%
 4574 r%=vpua%
 4576 IF nicon%=0 THEN =r%
 4578 lo%=0:hi%=nicon%-1
 4580 REPEAT
 4582   md%=(lo%+hi%) DIV 2
 4584   c%=icon%!(md%*4)
 4586   IF c%=u% THEN r%=276+md%:lo%=hi%+1
 4588   IF c%<u% THEN lo%=md%+1
 4590   IF c%>u% THEN hi%=md%-1
 4592 UNTIL lo%>hi%
 4594 =r%
 4596 :
 4598 REM ---- the block elements, U+2580 to U+259F, generated not stored ----
 4600 REM All 32 are EXACT at 8x8 - the eighths land on pixel boundaries in both
 4602 REM directions - so these are the characters themselves, not an approximation
 4604 REM of them. The three shades are caught earlier, by FNv_uni2 and the DEC set.
 4606 DEF PROCv_block
 4608 LOCAL i%,n%,y%,m%,t%,b%
 4610 FOR i%=0 TO 31
 4612   FOR y%=0 TO ch%-1:font%?((768+i%)*ch%+y%)=0:NEXT
 4614 NEXT
 4616 FOR y%=0 TO ch% DIV 2-1:font%?(768*ch%+y%)=&FF:NEXT
 4618 FOR n%=1 TO 8
 4620   FOR y%=ch%-n% TO ch%-1:font%?((768+n%)*ch%+y%)=&FF:NEXT
 4622 NEXT
 4624 FOR n%=1 TO 7
 4626   m%=&100-2^(8-n%)
 4628   FOR y%=0 TO ch%-1:font%?((768+&10-n%)*ch%+y%)=m%:NEXT
 4630 NEXT
 4632 FOR y%=0 TO ch%-1:font%?((768+&10)*ch%+y%)=&0F:NEXT
 4634 font%?((768+&14)*ch%)=&FF
 4636 FOR y%=0 TO ch%-1:font%?((768+&15)*ch%+y%)=&01:NEXT
 4638 RESTORE 4664
 4640 FOR n%=0 TO 9
 4642   READ m%
 4644   t%=0:b%=0
 4646   IF (m% AND 1)<>0 THEN t%=t% OR &F0
 4648   IF (m% AND 2)<>0 THEN t%=t% OR &0F
 4650   IF (m% AND 4)<>0 THEN b%=b% OR &F0
 4652   IF (m% AND 8)<>0 THEN b%=b% OR &0F
 4654   FOR y%=0 TO ch% DIV 2-1:font%?((790+n%)*ch%+y%)=t%:font%?((790+n%)*ch%+y%+ch% DIV 2)=b%:NEXT
 4656 NEXT
 4658 ENDPROC
 4660 :
 4662 REM 2596-259F: upper-left 1, upper-right 2, lower-left 4, lower-right 8.
 4664 DATA 4,8,1,13,9,7,11,2,6,14
 4666 :
 4668 REM A codepoint then its eight rows, in codepoint order. docs/glyphs.md
 4670 REM names them and says where each came from.
 4672 DATA 27
 4674 DATA &E0B0,192,224,248,254,254,248,224,192,&E0B1,192,48,12,2,2,8,48,192,&E0B2,3,7,31,127,127,31,7,3,&E0B3,3,12,48,64,64,48,12,3
 4676 DATA &E623,0,24,24,255,126,60,60,36,&E795,255,255,223,223,255,255,255,0,&EBC6,24,56,40,12,68,68,160,40,&EF70,204,232,127,31,60,126,231,194
 4678 DATA &F013,24,126,255,102,102,255,126,24,&F028,0,18,51,247,247,51,18,0,&F031,24,24,24,60,36,60,102,231,&F192,60,66,129,153,153,129,66,60
 4680 DATA &F488,255,249,255,129,129,129,255,0,&F489,255,129,161,177,173,129,255,0,&F003B,219,219,0,219,219,0,219,219,&F0150,60,66,129,145,137,129,66,60
 4682 DATA &F027C,252,254,2,62,48,48,48,48,&F0322,0,126,1,1,66,255,0,0,&F0379,255,129,129,129,129,255,24,0,&F03D6,24,118,243,191,158,203,126,24
 4684 DATA &F0443,0,0,64,255,192,0,0,0,&F04E1,0,0,31,2,64,248,64,0,&F075A,7,63,33,33,39,231,231,224,&F0960,30,63,51,63,30,255,255,255
 4686 DATA &F0ED1,0,252,215,223,215,252,0,0,&F0EE0,60,126,255,211,203,254,126,56,&F0F86,60,66,49,185,153,129,66,0
4688 :
4690 REM ---- double box drawing, U+2550 to U+256C ----
4692 REM
4694 REM 598 occurrences across fastfetch's builtin logos, the largest gap left
4696 REM after the icons. The geometry is this font's own: the DEC DATA above puts
4698 REM a single horizontal on row 3 and a single vertical on columns 3-4, so the
4700 REM doubles straddle them - rows 2 and 4, columns 1-2 and 5-6. Straddling is
4702 REM what makes the two sets align, the single line's position being the
4704 REM double's gap.
4706 REM
4708 REM STORED, NOT GENERATED, unlike braille and the block elements, and that is
4710 REM a judgement rather than a habit: their rule is one line of arithmetic and
4712 REM this one is four cases - a stroke runs through, or stops at the near
4714 REM perpendicular stroke, or caps the whole footprint, or breaks in the
4716 REM middle. tools/mkdbox.py holds that rule with a test that proves every
4718 REM glyph's edge matches its declared arms, which is what makes any two of
4720 REM them join. Here the machine reads 232 bytes it cannot get wrong.
4722 DEF PROCv_dbox
4724 LOCAL i%,y%,b%
4726 RESTORE 4740
4728 FOR i%=0 TO 28
4730   FOR y%=0 TO ch%-1:READ b%:font%?((800+i%)*ch%+y%)=b%:NEXT
4732 NEXT
4734 ENDPROC
4736 :
4738 REM Eight rows per glyph, four glyphs to a line, in codepoint order.
4740 DATA 0,0,255,0,255,0,0,0,102,102,102,102,102,102,102,102,0,0,31,24,31,24,24,24,0,0,0,127,102,102,102,102
4742 DATA 0,0,127,96,103,102,102,102,0,0,248,24,248,24,24,24,0,0,0,254,102,102,102,102,0,0,254,6,230,102,102,102
4744 DATA 24,24,31,24,31,0,0,0,102,102,102,127,0,0,0,0,102,102,103,96,127,0,0,0,24,24,248,24,248,0,0,0
4746 DATA 102,102,102,254,0,0,0,0,102,102,230,6,254,0,0,0,24,24,31,24,31,24,24,24,102,102,102,103,102,102,102,102
4748 DATA 102,102,103,96,103,102,102,102,24,24,248,24,248,24,24,24,102,102,102,230,102,102,102,102,102,102,230,6,230,102,102,102
4750 DATA 0,0,255,0,255,24,24,24,0,0,0,255,102,102,102,102,0,0,255,0,231,102,102,102,24,24,255,0,255,0,0,0
4752 DATA 102,102,102,255,0,0,0,0,102,102,231,0,255,0,0,0,24,24,255,24,255,24,24,24,102,102,102,255,102,102,102,102
4754 DATA 102,102,231,0,231,102,102,102
4756 :
4758 REM ---- sextants and octants: braille with a different grid ----
4760 REM
4762 REM 2x3 and 2x4, and the same trick as braille - the shape IS the codepoint.
4764 REM What differs is that Unicode does not encode the combinations that already
4766 REM have a character of their own, so the codepoints run over the masks with
4768 REM 26 of 256 and 4 of 64 missing. Walking the masks in order and skipping
4770 REM those reproduces the codepoint order exactly, which was checked against
4772 REM Unicode's own names for all 290 rather than assumed.
4774 REM
4776 REM The excluded masks are the ones this table draws elsewhere already:
4778 REM space, the halves, the quadrants, the quarter blocks, the full block.
4780 DEF PROCv_legacy
4782 LOCAL m%,r%,y%,b%,i%,n%,y0%,y1%
4784 FOR m%=0 TO 255
4786   FOR r%=0 TO 3
4788     b%=0
4790     IF (m% AND 2^(r%*2))<>0 THEN b%=b% OR &F0
4792     IF (m% AND 2^(r%*2+1))<>0 THEN b%=b% OR &0F
4794     font%?((832+m%)*ch%+r%*2)=b%
4796     font%?((832+m%)*ch%+r%*2+1)=b%
4798   NEXT
4800 NEXT
4802 FOR m%=0 TO 63
4804   FOR r%=0 TO 2
4806     b%=0
4808     IF (m% AND 2^(r%*2))<>0 THEN b%=b% OR &F0
4810     IF (m% AND 2^(r%*2+1))<>0 THEN b%=b% OR &0F
4812     y0%=r%*3:y1%=y0%+2
4814     IF r%=2 THEN y0%=6:y1%=7
4816     FOR y%=y0% TO y1%:font%?((1088+m%)*ch%+y%)=b%:NEXT
4818   NEXT
4820 NEXT
4822 DIM octm% 229, sexm% 59, oflg% 255
4824 RESTORE 4858
4826 FOR m%=0 TO 255:oflg%?m%=0:NEXT
4828 FOR i%=1 TO 26:READ b%:oflg%?b%=1:NEXT
4830 n%=0
4832 FOR m%=0 TO 255
4834   IF oflg%?m%=0 THEN octm%?n%=m%:n%=n%+1
4836 NEXT
4838 FOR m%=0 TO 63:oflg%?m%=0:NEXT
4840 FOR i%=1 TO 4:READ b%:oflg%?b%=1:NEXT
4842 n%=0
4844 FOR m%=0 TO 63
4846   IF oflg%?m%=0 THEN sexm%?n%=m%:n%=n%+1
4848 NEXT
4850 nmap%=1
4852 ENDPROC
4854 :
4856 REM The 26 octant masks Unicode leaves out, then the 4 sextant ones.
4858 DATA 0,1,2,3,5,10,15,20,40,63,64,80,85,90,95,128,160,165,170,175,192,240,245,250,252,255
4860 DATA 0,21,42,63
4862 :
4864 REM ---- Latin-1, U+00A0 to U+00FF ----
4866 REM
4868 REM MOST OF THIS BLOCK IS NOT DRAWN. Fifty-five of the ninety-six are a letter
4870 REM the harvested driver font already has, plus a mark, so they are composed
4872 REM here at boot from the machine's OWN font - an accented letter then matches
4874 REM the unaccented one beside it exactly, which importing from a desktop font
4876 REM could never do.
4878 REM
4880 REM That works because of where this font sits in the cell, measured off
4882 REM results/RESFONT rather than assumed: lowercase occupies rows 2-6, leaving
4884 REM two free rows above for the accent; capitals occupy 0-6, so they drop one
4886 REM row and take a one-row accent; i gives up its dot, which is exactly what
4888 REM the accent replaces; and row 7 is free on both, where a cedilla goes.
4890 REM
4892 REM The rest - ligatures, fractions, currency, punctuation - have no base to
4894 REM build on and arrive as DATA from tools/mklatin.py.
4896 REM
4898 REM NOTE FOR WHOEVER CHECKS THIS: the glass test cannot. It compares the
4900 REM screen against the model, and both use this same table, so a wrong SHAPE
4902 REM matches itself perfectly. Only an eye catches these.
4904 DEF PROCv_latin
4906 LOCAL i%,y%,b%,u%,n%,c%,a%
4908 FOR i%=0 TO 95
4910   FOR y%=0 TO ch%-1:font%?((1152+i%)*ch%+y%)=0:NEXT
4912 NEXT
4914 RESTORE 4991
4916 READ n%
4918 FOR i%=1 TO n%
4920   READ u%
4922   FOR y%=0 TO ch%-1:READ b%:font%?((1152+u%-&A0)*ch%+y%)=b%:NEXT
4924 NEXT
4926 READ n%
4928 FOR i%=1 TO n%
4930   READ u%,c%,a%
4932   PROCv_acc(1152+u%-&A0,c%,a%)
4934 NEXT
4936 ENDPROC
4938 :
4940 REM The base glyph, then the mark. Accent 6 is the cedilla, which sits below
4942 REM and shifts nothing; 7 is the slash through O, which overlays.
4944 DEF PROCv_acc(s%,c%,a%)
4946 LOCAL y%,up%,t%,b%
4948 FOR y%=0 TO ch%-1:font%?(s%*ch%+y%)=font%?(c%*ch%+y%):NEXT
4950 IF c%=105 THEN font%?(s%*ch%)=0
4952 IF a%=6 THEN font%?(s%*ch%+7)=font%?(s%*ch%+7) OR &18:ENDPROC
4954 IF a%=7 THEN PROCv_slash(s%):ENDPROC
4956 RESTORE 5028
4958 FOR y%=0 TO a%:READ up%,t%,b%:NEXT
4960 IF c%>=65 AND c%<=90 THEN PROCv_drop(s%):font%?(s%*ch%)=up%:ENDPROC
4962 font%?(s%*ch%)=t%:font%?(s%*ch%+1)=b%
4964 ENDPROC
4966 :
4968 DEF PROCv_slash(s%)
4970 LOCAL y%
4972 FOR y%=1 TO 6:font%?(s%*ch%+y%)=font%?(s%*ch%+y%) OR 2^y%:NEXT
4974 ENDPROC
4976 :
4978 DEF PROCv_drop(s%)
4980 LOCAL y%
4982 FOR y%=ch%-1 TO 1 STEP -1:font%?(s%*ch%+y%)=font%?(s%*ch%+y%-1):NEXT
4984 font%?(s%*ch%)=0
4986 ENDPROC
4988 :
4990 REM Codepoint then eight rows, for the ones with nothing to build on.
4991 DATA 32
4992 DATA &A1,16,0,0,16,16,16,16,16,&A2,8,28,56,40,32,56,28,8,&A4,195,126,102,66,66,102,127,195,&A5,102,36,52,60,24,60,24,24
4994 DATA &A6,16,16,16,0,0,16,16,16,&A7,28,48,56,44,52,28,12,56,&A8,0,102,0,0,0,0,0,0,&A9,60,66,185,161,161,185,66,60
4996 DATA &AA,60,6,62,102,102,126,0,126,&AB,17,51,102,204,204,102,51,17,&AC,0,0,255,255,1,1,0,0,&AE,60,66,189,189,185,165,66,60
4998 DATA &AF,0,126,0,0,0,0,0,0,&B4,12,24,0,0,0,0,0,0,&B5,72,72,72,72,76,124,64,64,&B6,60,116,116,52,20,20,20,20
5000 DATA &B8,0,0,0,0,0,24,48,0,&BA,60,102,66,66,102,60,0,126,&BB,136,204,102,51,51,102,204,136,&BC,32,32,32,48,8,8,28,12
5002 DATA &BD,32,32,32,48,88,4,8,24,&BE,48,16,16,48,8,8,28,12,&BF,8,0,8,24,16,32,32,60,&C6,30,24,40,46,44,120,72,78
5004 DATA &D0,60,38,34,114,98,34,38,60,&D7,0,0,66,36,24,36,66,0,&DE,64,112,124,68,76,120,64,64,&DF,120,72,88,80,88,76,68,124
5006 DATA &E6,126,27,25,127,216,152,216,127,&F0,56,56,56,108,68,68,108,56,&F7,24,24,0,255,255,0,24,24,&FE,32,40,60,36,36,60,32,32
5008 REM Then codepoint, base character, accent - and last the accent shapes
5010 REM themselves: one row for a dropped capital, two for lowercase.
5012 DATA 55
5014 DATA &C0,65,0,&C1,65,1,&C2,65,2,&C3,65,3,&C4,65,4,&C5,65,5,&C7,67,6,&C8,69,0
5016 DATA &C9,69,1,&CA,69,2,&CB,69,4,&CC,73,0,&CD,73,1,&CE,73,2,&CF,73,4,&D1,78,3
5018 DATA &D2,79,0,&D3,79,1,&D4,79,2,&D5,79,3,&D6,79,4,&D8,79,7,&D9,85,0,&DA,85,1
5020 DATA &DB,85,2,&DC,85,4,&DD,89,1,&E0,97,0,&E1,97,1,&E2,97,2,&E3,97,3,&E4,97,4
5022 DATA &E5,97,5,&E7,99,6,&E8,101,0,&E9,101,1,&EA,101,2,&EB,101,4,&EC,105,0,&ED,105,1
5024 DATA &EE,105,2,&EF,105,4,&F1,110,3,&F2,111,0,&F3,111,1,&F4,111,2,&F5,111,3,&F6,111,4
5026 DATA &F8,111,7,&F9,117,0,&FA,117,1,&FB,117,2,&FC,117,4,&FD,121,1,&FF,121,4
5028 DATA 96,96,48,12,12,24,24,24,36,108,50,76,102,102,0,36,56,40,0,0,0,0,0,0
5030 :
5032 REM ---- the legacy diagonals and eighths, U+1FB3C to U+1FB8B ----
5034 REM
5036 REM No font on the build machine has this block - DejaVu, FreeMono, Noto and
5038 REM the Nerd Font off archbox all miss the whole of it - so there was nothing to
5040 REM rasterise from. Unicode's own names turned out to be enough: each of the
5042 REM 80 says exactly what it is, and tools/mklegacy.py reads the geometry
5044 REM straight out of the words. A line between two named boundary points cuts
5046 REM the cell in two and the half holding the named corner is filled.
5048 DEF PROCv_diag
5050 LOCAL i%,y%,b%
5052 RESTORE 5118
5054 FOR i%=0 TO 79
5056   FOR y%=0 TO ch%-1:READ b%:font%?((1248+i%)*ch%+y%)=b%:NEXT
5058 NEXT
5060 ENDPROC
5062 :
5064 REM ---- and the last two dozen, which are a list rather than a family ----
5066 REM
5068 REM Scanned linearly, not bisected as the icons are: there are 25 of them and
5070 REM the logos ask for one 94 times in total, so the table is smaller than the
5072 REM code to search it cleverly would be.
5074 DEF PROCv_sym
5076 LOCAL i%,y%,b%
5078 RESTORE 5160
5080 READ nsym%
5082 DIM sym% nsym%*4-1
5084 FOR i%=0 TO nsym%-1
5086   READ b%:sym%!(i%*4)=b%
5088   FOR y%=0 TO ch%-1:READ b%:font%?((1328+i%)*ch%+y%)=b%:NEXT
5090 NEXT
5092 ENDPROC
5094 :
5096 REM Last in the chain, so it carries the replacement glyph for everything.
5098 DEF FNv_sym(u%)
5100 LOCAL i%,r%
5102 r%=vrep%
5104 IF nsym%=0 THEN =r%
5106 FOR i%=0 TO nsym%-1
5108   IF sym%!(i%*4)=u% THEN r%=1328+i%
5110 NEXT
5112 =r%
5114 :
5116 REM Eight rows per glyph, four to a line, U+1FB3C upwards in order.
5118 DATA 0,0,0,0,0,0,192,224,0,0,0,0,0,128,240,252,0,0,0,128,128,192,224,240,0,0,0,128,224,240,252,254
5120 DATA 0,128,128,192,192,224,224,240,31,63,255,255,255,255,255,255,1,15,255,255,255,255,255,255,15,31,63,127,127,255,255,255
5122 DATA 1,3,15,31,127,255,255,255,15,31,31,63,63,127,127,255,0,0,0,7,63,255,255,255,0,0,0,0,0,0,3,7
5124 DATA 0,0,0,0,0,1,15,127,0,0,0,1,1,3,7,15,0,0,0,1,7,15,63,127,0,1,1,3,3,7,7,15
5126 DATA 248,252,255,255,255,255,255,255,128,240,254,255,255,255,255,255,240,248,252,254,254,255,255,255,128,192,240,248,254,255,255,255
5128 DATA 240,248,248,252,252,254,254,255,0,0,0,224,252,255,255,255,255,255,255,255,255,255,63,31,255,255,255,255,255,127,15,1
5130 DATA 255,255,255,127,127,63,31,15,255,255,255,127,31,15,3,1,255,127,127,63,63,31,31,15,224,192,0,0,0,0,0,0
5132 DATA 252,224,0,0,0,0,0,0,240,224,192,128,128,0,0,0,254,252,240,224,128,0,0,0,240,224,224,192,192,128,128,0
5134 DATA 255,255,255,248,192,0,0,0,255,255,255,255,255,255,252,248,255,255,255,255,255,254,240,128,255,255,255,254,254,252,248,240
5136 DATA 255,255,255,254,248,240,192,128,255,254,254,252,252,248,248,240,7,3,0,0,0,0,0,0,63,7,0,0,0,0,0,0
5138 DATA 15,7,3,1,1,0,0,0,127,63,15,7,1,0,0,0,15,7,7,3,3,1,1,0,255,255,255,31,3,0,0,0
5140 DATA 0,128,192,230,230,192,128,0,0,24,60,126,102,0,0,0,0,1,3,103,103,3,1,0,0,0,0,102,126,60,24,0
5142 DATA 240,224,192,128,128,192,224,240,255,126,60,24,0,0,0,0,15,7,3,1,1,3,7,15,0,0,0,0,24,60,126,255
5144 DATA 64,64,64,64,64,64,64,64,32,32,32,32,32,32,32,32,16,16,16,16,16,16,16,16,8,8,8,8,8,8,8,8
5146 DATA 4,4,4,4,4,4,4,4,2,2,2,2,2,2,2,2,0,255,0,0,0,0,0,0,0,0,255,0,0,0,0,0
5148 DATA 0,0,0,255,0,0,0,0,0,0,0,0,255,0,0,0,0,0,0,0,0,255,0,0,0,0,0,0,0,0,255,0
5150 DATA 128,128,128,128,128,128,128,255,255,128,128,128,128,128,128,128,255,1,1,1,1,1,1,1,1,1,1,1,1,1,1,255
5152 DATA 255,0,0,0,0,0,0,255,255,0,255,0,255,0,0,255,255,255,0,0,0,0,0,0,255,255,255,0,0,0,0,0
5154 DATA 255,255,255,255,255,0,0,0,255,255,255,255,255,255,0,0,255,255,255,255,255,255,255,0,3,3,3,3,3,3,3,3
5156 DATA 7,7,7,7,7,7,7,7,31,31,31,31,31,31,31,31,63,63,63,63,63,63,63,63,127,127,127,127,127,127,127,127
5158 REM Then codepoint and eight rows, in codepoint order.
5160 DATA 25
5162 DATA &192,12,24,24,16,16,16,16,48,&384,0,15,30,28,56,112,224,0,&393,124,64,64,64,64,64,64,64,&3C6,60,126,90,90,126,60,24,24
5164 DATA &207F,188,230,198,134,198,198,198,198,&221A,4,4,8,8,104,48,16,16,&221E,0,102,153,153,153,102,0,0,&2229,60,102,66,66,66,66,66,66
5166 DATA &2248,0,249,159,0,249,143,0,0,&2261,255,255,0,255,0,0,255,0,&2302,8,24,36,98,66,66,66,126,&2310,0,0,255,255,128,128,0,0
5168 DATA &2320,8,16,16,16,16,16,16,16,&23BA,255,0,0,0,0,0,0,0,&23BB,0,255,0,0,0,0,0,0,&23BC,0,0,0,0,0,255,0,0
5170 DATA &23BD,0,0,0,0,0,0,0,255,&2501,0,0,0,255,255,0,0,0,&257C,0,0,0,248,15,0,0,0,&257E,0,0,0,240,31,0,0,0
5172 DATA &25BA,0,192,248,254,248,192,0,0,&25C4,0,3,31,127,31,3,0,0,&25CF,60,126,255,255,255,255,126,60,&27E8,8,8,16,16,16,16,8,8
5174 DATA &27E9,16,16,8,8,8,8,16,16
