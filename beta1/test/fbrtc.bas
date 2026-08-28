   10 REM > FBRTC - read the 146818's OWN registers over the slow bus
   20 REM
   30 REM   co-processor OFF:  NEW  then  *EXEC FBRTC  then  RUN
   40 REM
   50 REM Reads. Writes nothing to the chip. FBRTCW does the writing.
   60 REM
   70 REM The MOS cannot see registers 0-13. OSBYTE &A1 addresses CMOS
   80 REM OFFSETS 0-49, which are chip registers 14-63, so the clock and
   90 REM the four control registers are out of its reach entirely. The
  100 REM only route to them is the system VIA slow bus - spec 5.5b-nonies.
  110 REM
  120 REM The sequence is the Advanced Master Reference Manual's, decoded
  130 REM against its own port B bit map (its comment column is misaligned
  140 REM in the PDF, its bytes are not):
  150 REM
  160 REM   &02 idle    &82 AS high   DDRA=&FF   PA=register number
  170 REM   &C2 CE on   &42 AS low, address latched
  180 REM   &49 R/W high = READ        DDRA=&00 - port A to input FIRST
  190 REM   &4A DS high  read PA  &42 DS low  &02 CE off  DDRA=&00
  200 REM
  210 REM That is Motorola-mode 146818 timing: address latched on the
  220 REM falling edge of AS, data taken while DS is high.
  230 REM
  240 REM SEI around the whole sequence is not optional. Port A and the
  250 REM addressable latch are shared with the KEYBOARD and the SOUND
  260 REM chip, so the 100Hz key scan landing in the middle of it would
  270 REM strobe whatever it left on the bus into whichever register was
  280 REM last latched. That is what the manual's "extreme care" means.
  290 REM
  300 REM Register C clears when it is read, so it is read twice a second
  310 REM apart. Flags that come back set are being regenerated, and a
  320 REM regenerated IRQF is the free-running unclaimed interrupt that
  330 REM 5.5b-quater's crash has been looking for.
  340 :
  350 rf$="RESRTC"
  360 ON ERROR PROCerr:END
  370 DIM code% 120
  380 PROCasm
  390 PRINT "spooling to ";rf$
  400 OSCLI("SPOOL "+rf$)
  410 PRINT "== FBRTC =="
  412 REM READ D FIRST, ONCE, BEFORE ANYTHING ELSE TOUCHES THE CHIP.
  414 REM VRT is set to 1 BY THE ACT OF READING REGISTER D, so only the
  415 REM first read since power-on carries information: after that it
  416 REM reads 1 whatever the battery is doing. On 2026-08-21 the dump
  417 REM read &00 here and the control section, later in the same run,
  418 REM read &80 - and the &80 is the meaningless one. Spec 5.5b-undecies.
  419 PRINT "== VRT FIRST READ == D ";~FNrd(13)
  420 PROCdump
  430 PROCclock
  440 PROCctrl
  450 PRINT "== END =="
  460 OSCLI("SPOOL")
  470 PRINT
  480 PRINT "FBRTC done - ";rf$;" is on the share."
  490 END
  500 :
 1000 DEF PROCdump
 1010 LOCAL r%,i%
 1020 PRINT "== REGISTERS 0-63 =="
 1030 FOR r%=0 TO 63 STEP 8
 1040   PRINT FNh(r%);": ";
 1050   FOR i%=0 TO 7:PRINT FNh(FNrd(r%+i%));" ";:NEXT
 1060   PRINT
 1070 NEXT
 1080 ENDPROC
 1090 :
 1100 DEF PROCclock
 1110 PRINT "== CLOCK REGISTERS =="
 1120 PRINT "sec ";~FNrd(0);" min ";~FNrd(2);" hour ";~FNrd(4)
 1130 PRINT "dow ";~FNrd(6);" date ";~FNrd(7);" month ";~FNrd(8);" year ";~FNrd(9)
 1140 PRINT "alarm sec ";~FNrd(1);" min ";~FNrd(3);" hour ";~FNrd(5)
 1150 ENDPROC
 1160 :
 1170 REM The four control registers, bit by bit. These are the answer to
 1180 REM every question outstanding about this chip.
 1190 DEF PROCctrl
 1200 LOCAL a%,b%,c%,d%,c2%,t%
 1210 a%=FNrd(10):b%=FNrd(11):c%=FNrd(12):d%=FNrd(13)
 1220 PRINT "== CONTROL =="
 1230 PRINT "A ";~a%;"  UIP ";FNb(a%,7);" DV ";(a% AND &70) DIV 16;" RS ";a% AND 15
 1240 PRINT "  DV 2 is the only running setting; RS 0 disables the periodic tick"
 1250 PRINT "B ";~b%;"  SET ";FNb(b%,7);" PIE ";FNb(b%,6);" AIE ";FNb(b%,5);" UIE ";FNb(b%,4)
 1260 PRINT "  SQWE ";FNb(b%,3);" DM ";FNb(b%,2);" 24/12 ";FNb(b%,1);" DSE ";FNb(b%,0)
 1270 PRINT "  DM 1 is BINARY counting - the MOS assumes BCD, so DM 1 alone"
 1280 PRINT "  would explain a year printing as 197B and an hour as F9."
 1290 PRINT "  PIE with RS non-zero is a free-running IRQ nothing claims."
 1300 PRINT "C ";~c%;"  IRQF ";FNb(c%,7);" PF ";FNb(c%,6);" AF ";FNb(c%,5);" UF ";FNb(c%,4)
 1310 PRINT "D ";~d%;"  VRT ";FNb(d%,7);"  <- SECOND READ, IGNORE IT"
 1320 PRINT "  The VRT that means anything is the VRT FIRST READ line at"
 1330 PRINT "  the top: 0 there says backup power has been lost. Reading"
 1335 PRINT "  register D sets the bit, so this one always says 1."
 1340 REM One second by the HOST's 100Hz TIME, which is the system VIA and
 1350 REM has nothing to do with this chip. Safe here - we are on the host,
 1360 REM so no Tube transaction is involved.
 1370 t%=TIME:REPEAT UNTIL TIME>t%+100
 1380 c2%=FNrd(12)
 1390 PRINT "C again after 1s ";~c2%;"  IRQF ";FNb(c2%,7);" PF ";FNb(c2%,6);" UF ";FNb(c2%,4)
 1400 PRINT "  C clears when read. Anything set again is being REGENERATED."
 1410 ENDPROC
 1420 :
 1421 REM Two hex digits, so the dump lines up as a table - it is the
 1422 REM record that gets compared against the replacement chip.
 1424 DEF FNh(v%)
 1426 =RIGHT$("0"+STR$~v%,2)
 1428 :
 1430 REM Negated: BBC BASIC prints TRUE as -1, and a bit is 1 or 0.
 1440 DEF FNb(v%,n%)
 1445 =-((v% AND (2^n%))<>0)
 1450 :
 1460 REM X = register number, returns the byte. USR gives A back in the
 1470 REM low byte; the routine leaves the data in A through TYA.
 1480 DEF FNrd(r%)
 1490 A%=0:X%=r%:Y%=0
 1500 =USR(rd) AND &FF
 1510 :
 1520 DEF PROCasm
 1530 LOCAL o%
 1540 FOR o%=0 TO 2 STEP 2
 1550 P%=code%
 1560 [OPT o%
 1570 .rd
 1580 PHP:SEI
 1590 LDA #&02:STA &FE40
 1600 LDA #&82:STA &FE40
 1610 LDA #&FF:STA &FE43
 1620 STX &FE41
 1630 LDA #&C2:STA &FE40
 1640 LDA #&42:STA &FE40
 1650 LDA #&49:STA &FE40
 1660 LDA #&00:STA &FE43
 1670 LDA #&4A:STA &FE40
 1680 LDA &FE41:TAY
 1690 LDA #&42:STA &FE40
 1700 LDA #&02:STA &FE40
 1710 LDA #&00:STA &FE43
 1720 TYA
 1730 PLP
 1740 RTS
 1750 ]
 1760 NEXT
 1770 ENDPROC
 1780 :
 1790 DEF PROCerr
 1800 OSCLI("SPOOL")
 1810 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1820 REPORT:PRINT
 1830 ENDPROC
