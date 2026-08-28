   10 REM > TUBERATE - TUBEBARE with the rate as the dial instead of the nap.
   20 REM Still short enough to type, because the machine it runs on has no
   30 REM filing system once LANMANAGER is unplugged.
   40 REM
   50 REM 2026-08-22: the ARM froze in 24s (ROM in) and just over a minute
   60 REM (ROM out), and the 65C102 passed ten minutes. That is either a
   70 REM difference between the cores or simply a difference in SPEED - a
   80 REM 6502 may only be too slow to reach the rate that breaks it. Nap
   90 REM length cannot settle that because the same nap is a different rate
  100 REM on each core. A TARGET RATE can.
  110 REM
  120 REM Set want% to the naps per second you want. It times the default nap
  130 REM for one second, scales it to hit the target, and reports what it
  140 REM actually achieved. Each nap makes two INKEY(0) calls, so the Tube
  150 REM transaction rate is about twice want%.
  160 REM
  170 REM   ARM survives at the 6502's rate   rate alone explains everything,
  180 REM                                     no core is special, and there
  190 REM                                     is a SAFE RATE to find
  200 REM   ARM dies at the 6502's rate       the ARM core is genuinely at
  210 REM                                     fault and there is an upstream
  220 REM
  230 REM If a safe rate exists, the question that decides the project is
  240 REM whether it is above PTERM's polling - which was 53 reads a second.
  242 REM
  244 REM BUT IT MAY NOT BE A RATE AT ALL. Every result so far fits a fixed
  246 REM TRANSACTION BUDGET just as well, and a budget means there is no
  248 REM safe rate - only a slower death. TUBEBARE froze the ARM at 97475
  250 REM naps, about 195000 transactions. The 65C102 passed ten minutes at
  251 REM 43.48 nps, which is only about 52000 - a quarter of the ARM's
  252 REM figure - so it did not survive the ARM's ordeal, it stopped early.
  253 REM
  254 REM So the test ends on a COUNT, not on patience. targ% is transactions
  255 REM and 200000 clears the ARM's failure figure. At 87 a second that is
  256 REM about 38 minutes: long, but it is the first run that can tell a
  257 REM threshold from a budget, and a shorter one cannot.
  258 REM
  260 REM   *FX 151,230,2   CTRL-BREAK  *BASIC     the 65C102
  270 REM   *FX 151,230,15  CTRL-BREAK  *ARMBASIC  the ARM
  280 :
  281 REM Label every printed field. A run on 2026-08-22 printed c% in
  282 REM the slot meant for elapsed centiseconds, and the screen read as
  283 REM though the machine were forty times faster than it was. Third
  284 REM time a run could not state its own conditions, after the missing
  285 REM build stamp and the missing clock. Print secs, not cs.
  286 REM
  287 REM 2026-08-23: MODE 7 clears 200000 easily, so that target no longer
  288 REM discriminates. Retargeted as a tube_delay SWEEP: run flat out and
  289 REM demand ten times the old count, so a bad delay shows as a number.
  290 want%=1400:targ%=2000000
  300 n%=20000:c%=0
  310 t0%=TIME:REPEAT:FOR i%=1 TO n%:NEXT:c%=c%+1:UNTIL TIME-t0%>=100
  320 n%=n%*c%/want%:IF n%<1 THEN n%=1
  330 PRINT "TUBERATE b0823a want=";want%;" targ=";targ%
  332 PRINT "free run ";c%;" nps, nap now ";n%
  334 PRINT "MODE 7 ON THE HOST OR THE RUN IS VOID - mode 0 froze 4 of 4."
  336 PRINT "LANMANAGER may stay INSERTED; mode 7 passed with it in."
  338 PRINT
  340 c%=0:t0%=TIME
  350 REPEAT
  360   FOR i%=1 TO n%:NEXT
  370   j%=INKEY(0):j%=INKEY(0)
  380   c%=c%+1
  390   IF c% MOD 25=0 THEN e%=TIME-t0%+1:PRINT "tx=";c%*2;" secs=";e%/100;" nps=";c%*100/e%
  395   IF c%*2>=targ% THEN PRINT "PASSED ";c%*2;" transactions":END
  400 UNTIL FALSE
