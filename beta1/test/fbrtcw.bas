   10 REM > FBRTCW - set the clock and the control bits over the slow bus
   20 REM
   30 REM   co-processor OFF:  NEW  then  *EXEC FBRTCW  then  RUN
   40 REM
   50 REM Run FBRTC FIRST and keep RESRTC. This overwrites what it read.
   60 REM
   70 REM WRITES REGISTERS 0-13 ONLY - the clock and the four control
   80 REM registers. Registers 14-63 are the CMOS configuration and are
   90 REM never touched here, so nothing this program does can cost you
  100 REM the machine's setup.
  110 REM
  120 REM What it does, in the order the 146818 requires:
  130 REM
  140 REM   B := &82   SET stops the counters transferring, so the time
  150 REM              registers can be written without an update landing
  160 REM              in the middle. Also 24-hour, BCD, ALL INTERRUPT
  170 REM              ENABLES OFF - PIE, AIE and UIE cleared.
  180 REM   A := &20   DV = 010, the one setting that runs the 32.768kHz
  190 REM              oscillator. RS = 0000 disables the periodic tick
  200 REM              at source, so PF cannot even be raised.
  210 REM   0-9        seconds, minutes, hours, day, date, month, year,
  220 REM              in BCD because B now says BCD.
  230 REM   B := &02   SET released - the counters resume within a second.
  240 REM   C read     clears any flag left standing.
  250 REM
  260 REM This is the whole of the free-running-IRQ hypothesis closed out
  270 REM by construction: after this the chip cannot raise an interrupt.
  280 REM If the co-processor still dies with a socket open, the RTC is
  290 REM eliminated - and if it stops dying, 5.5b-quater has its cause.
  300 REM
  310 REM The MOS is not involved in any of this. It cannot see these
  320 REM registers at all - see FBRTC and spec 5.5b-nonies.
  330 :
  340 REM Stamped by tools/rtcarm.sh. Day of week is 1=Sunday.
  350 yr%=26:mo%=08:dm%=21:dw%=6:hr%=22:mi%=38:se%=20
  360 rf$="RESRTCW"
  370 ON ERROR PROCerr:END
  380 DIM code% 200
  390 PROCasm
  400 PRINT "spooling to ";rf$
  410 OSCLI("SPOOL "+rf$)
  420 PRINT "== FBRTCW =="
  430 PRINT "== BEFORE == A ";~FNrd(10);" B ";~FNrd(11);" C ";~FNrd(12);" D ";~FNrd(13)
  440 PRINT "== BEFORE CLOCK == ";FNmos
  450 PROCwr(11,&82)
  460 PROCwr(10,&20)
  470 PROCwr(0,FNbcd(se%))
  480 PROCwr(2,FNbcd(mi%))
  490 PROCwr(4,FNbcd(hr%))
  500 PROCwr(6,dw%)
  510 PROCwr(7,FNbcd(dm%))
  520 PROCwr(8,FNbcd(mo%))
  530 PROCwr(9,FNbcd(yr%))
  540 PROCwr(11,&02)
  550 dummy%=FNrd(12)
  560 PRINT "== AFTER == A ";~FNrd(10);" B ";~FNrd(11);" C ";~FNrd(12);" D ";~FNrd(13)
  570 PRINT "== AFTER REGS == sec ";~FNrd(0);" min ";~FNrd(2);" hour ";~FNrd(4);
  580 PRINT " date ";~FNrd(7);" month ";~FNrd(8);" year ";~FNrd(9)
  590 PRINT "== AFTER CLOCK == ";FNmos
  592 PRINT "== AFTER CLOCK FIXED == ";FNcent(FNmos)
  600 PRINT "== END =="
  610 OSCLI("SPOOL")
  620 PRINT
  630 PRINT "The AFTER REGS line is what the CHIP holds - it should read"
  640 PRINT "back as the BCD digits stamped in line 350."
  650 PRINT "The AFTER CLOCK line is what the MOS makes of it. If the chip"
  660 PRINT "is right and the MOS still prints nonsense, the fault is in"
  670 PRINT "how the MOS reads the year, not in the chip."
  675 PRINT "The century is the MOS's, not the chip's: MOS 3.20 prints 19"
  676 PRINT "unconditionally. FIXED is the same string with the pivot applied."
  680 END
  690 :
 1000 DEF FNbcd(n%)
 1010 =(n% DIV 10)*16+(n% MOD 10)
 1020 :
 1021 REM The century, repaired in the caller. This MOS prints 19xx for
 1022 REM every year the chip can hold, so a two-digit year below 80 is
 1023 REM taken as 20xx - the same pivot BeebWiki gives, and the same
 1024 REM answer the one-byte ROM patch gives without a ROM. Characters
 1025 REM 1 to 11 are "Fri,21 Aug ", 12 to 15 the year (spec 5.5b-duodecies).
 1026 DEF FNcent(s$)
 1027 IF MID$(s$,14,1)<"8" THEN =LEFT$(s$,11)+"20"+MID$(s$,14)
 1028 =s$
 1029 :
 1030 REM The MOS's own view, for comparison: OSWORD &0E type 0.
 1040 DEF FNmos
 1050 clk%?0=0
 1060 A%=&0E:X%=clk% AND 255:Y%=clk% DIV 256
 1070 CALL &FFF1
 1080 =$clk%
 1090 :
 1100 DEF FNrd(r%)
 1110 A%=0:X%=r%:Y%=0
 1120 =USR(rd) AND &FF
 1130 :
 1140 DEF PROCwr(r%,v%)
 1150 A%=0:X%=r%:Y%=v%
 1160 CALL wr
 1170 ENDPROC
 1180 :
 1190 REM Two routines, one bus sequence. Both hold SEI throughout: port A
 1200 REM and the addressable latch are shared with the keyboard and the
 1210 REM sound chip, and the 100Hz key scan interrupting a half-finished
 1220 REM access is precisely the corruption the manual warns about.
 1230 DEF PROCasm
 1240 LOCAL o%
 1250 DIM clk% 31
 1260 FOR o%=0 TO 2 STEP 2
 1270 P%=code%
 1280 [OPT o%
 1290 .rd
 1300 PHP:SEI
 1310 LDA #&02:STA &FE40
 1320 LDA #&82:STA &FE40
 1330 LDA #&FF:STA &FE43
 1340 STX &FE41
 1350 LDA #&C2:STA &FE40
 1360 LDA #&42:STA &FE40
 1370 LDA #&49:STA &FE40
 1380 LDA #&00:STA &FE43
 1390 LDA #&4A:STA &FE40
 1400 LDA &FE41:TAY
 1410 LDA #&42:STA &FE40
 1420 LDA #&02:STA &FE40
 1430 LDA #&00:STA &FE43
 1440 TYA
 1450 PLP
 1460 RTS
 1470 .wr
 1480 PHP:SEI
 1490 LDA #&02:STA &FE40
 1500 LDA #&82:STA &FE40
 1510 LDA #&FF:STA &FE43
 1520 STX &FE41
 1530 LDA #&C2:STA &FE40
 1540 LDA #&42:STA &FE40
 1550 LDA #&41:STA &FE40
 1560 LDA #&FF:STA &FE43
 1570 LDA #&4A:STA &FE40
 1580 STY &FE41
 1590 LDA #&42:STA &FE40
 1600 LDA #&02:STA &FE40
 1610 LDA #&00:STA &FE43
 1620 PLP
 1630 RTS
 1640 ]
 1650 NEXT
 1660 ENDPROC
 1670 :
 1680 DEF PROCerr
 1690 OSCLI("SPOOL")
 1700 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1710 REPORT:PRINT
 1720 ENDPROC
