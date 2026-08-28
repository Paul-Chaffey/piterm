   10 REM > FBBATT2 - phase 2 of the battery-backup test: READ IT BACK
   20 REM
   30 REM   after FBBATT, after a REAL power cut of five minutes or more:
   40 REM       NEW   then  *EXEC FBBATT2   then  RUN
   50 REM
   60 REM Reads only. Writes nothing.
   70 REM
   80 REM Three outcomes, and they are different faults:
   90 REM
  100 REM   markers held AND clock advanced by about the time the machine
  110 REM   was off  ->  the battery is backing up RAM and the oscillator.
  120 REM   That is the whole of battery backup working.
  130 REM
  140 REM   markers held, clock frozen at what FBBATT wrote  ->  the cell
  150 REM   is holding the RAM but the oscillator is not running on it.
  160 REM
  170 REM   markers gone, year back to 197B  ->  nothing is holding: the
  180 REM   cell is flat or the wrong way round, or the holder, its track
  190 REM   or the diode is open circuit. A meter across the cell IN the
  200 REM   holder with the machine off separates a dead cell from a break
  210 REM   in the wiring faster than any program can.
  220 :
  225 REM yy$ is stamped by tools/battarm.sh, and is TWO digits: this
  226 REM MOS prints every year as 19xx whatever the chip holds.
  230 yy$="26":dly%=45:rpt%=17
  240 rf$="RESBAT2"
  250 ON ERROR PROCerr:END
  260 DIM clk% 31
  270 PRINT "spooling to ";rf$
  280 OSCLI("SPOOL "+rf$)
  290 PRINT "== FBBATT2 phase 2 =="
  300 PRINT "== EXPECT == Delay ";dly%;" Repeat ";rpt%
  310 PRINT "== CLOCK NOW == ";FNclock
  320 PRINT "== STATUS NOW =="
  330 OSCLI("STATUS")
  340 PRINT "== END =="
  350 OSCLI("SPOOL")
  360 c$=FNclock
  370 PRINT
  380 IF FNyear(c$)=yy$ THEN PRINT "CLOCK SURVIVED - ";c$ ELSE PRINT "CLOCK LOST - ";c$
  390 PRINT "Delay and Repeat above: 45 and 17 means CMOS survived, 0 and"
  400 PRINT "0 means it did not."
  410 PRINT
  420 PRINT "The clock must have ADVANCED by roughly how long the machine"
  430 PRINT "was off. A frozen clock is not the same result as a running one."
  440 PRINT
  450 PRINT "Both files are on the share - tools/battcheck.py compares them."
  460 END
  470 :
 1000 DEF FNclock
 1010 clk%?0=0
 1020 A%=&0E:X%=clk% AND 255:Y%=clk% DIV 256
 1030 CALL &FFF1
 1040 =$clk%
 1050 :
 1060 DEF FNyear(s$)
 1070 =MID$(s$,14,2)
 1080 :
 1090 DEF PROCerr
 1100 OSCLI("SPOOL")
 1110 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1120 REPORT:PRINT
 1130 ENDPROC
