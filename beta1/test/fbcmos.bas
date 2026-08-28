   10 REM > FBCMOS - what is actually in CMOS, and is the clock sane?
   20 REM
   30 REM   CHAIN "FBCMOS"     copro 15, *ARMBASIC
   40 REM
   50 REM The user's theory: the CMOS/RTC battery is flat and something in
   60 REM there upsets the machine when the co-processor runs.
   70 REM
   80 REM What it cannot be: BASIC's TIME on a Master comes from the 100Hz
   90 REM system VIA interrupt, not the RTC chip, so a flat clock battery
  100 REM does not affect timing and does not explain FBSITN.
  110 REM
  120 REM What it could be: CMOS holds the machine's configuration, and
  130 REM Sprow's ROMs conventionally keep their network settings there. An
  140 REM Ethernet ROM reading corrupt configuration is plausible and
  150 REM nobody has ever looked.
  160 REM
  170 REM Uses *STATUS through *SPOOL rather than OSBYTE &A1. The OSBYTE
  180 REM route needs "SYS ... TO a%,x%,y%" to get the value back, and this
  190 REM BASIC rejects the TO clause with a syntax error - every SYS that
  200 REM works elsewhere in this project has no return list. *STATUS also
  210 REM gives the settings by NAME, which is far more use than 64 bytes
  220 REM of hex.
  230 REM
  240 REM Reads only. Writes nothing to CMOS.
  250 :
  260 rf$="RESCMOS"
  270 ON ERROR PROCerr:END
  280 PRINT "spooling *STATUS to ";rf$
  290 OSCLI("SPOOL "+rf$)
  300 OSCLI("STATUS")
  310 REM *TIME as well, since the clock is half the question. NOT *FX 0 -
  312 REM that reports the OS version AS AN ERROR by design, which is
  314 REM exactly the 247 this hit, and it was gratuitous anyway.
  316 OSCLI("TIME")
  320 OSCLI("SPOOL")
  330 PRINT
  340 PRINT "FBCMOS done - ";rf$;" is on the share."
  350 END
  360 :
 1000 DEF PROCerr
 1010 OSCLI("SPOOL")
 1020 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1030 REPORT:PRINT
 1040 ENDPROC
