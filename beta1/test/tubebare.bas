   10 REM > TUBEBARE - the smallest thing that reproduces the Tube crash,
   20 REM short enough to TYPE IN, because the test that needs it has no
   30 REM filing system.
   40 REM
   50 REM Every run in 5.5b-quater and 5.5b-quatersexies had the LANMANAGER
   60 REM ROM active - with a socket or without one, it was always there,
   70 REM hooking interrupts to service the interface. That is the variable
   80 REM that has never been removed, and it would explain both the fault
   90 REM and why an open socket makes it 3.6 times faster.
  100 REM
  105 REM RATE, NOT NAP COUNT, is what compares between cores. A 6502 copro
  106 REM runs the FOR at a fraction of the ARM's speed, so the same napn%
  107 REM is a quite different number of Tube transactions a second. The
  108 REM heartbeat prints nps% for that reason - read it off the first
  109 REM line, then change the 20000 at line 260 until the two cores are
  110 REM doing the same transactions a second, and only then compare.
  112 REM
  114 REM   *FX 151,230,2   then CTRL-BREAK    the 65C102, and *BASIC not
  116 REM   *FX 151,230,15  then CTRL-BREAK    back to ARM, *ARMBASIC
  118 REM
  119 REM   *ROMS                     find LANMANAGER's slot number
  120 REM   *UNPLUG <n>               disable it
  130 REM   CTRL-BREAK                ROMs are scanned at reset
  140 REM   *ARMBASIC                 the share is GONE, so type this in
  150 REM   RUN
  160 REM
  170 REM 0822j died at 24s with the ROM in. If this passes ten minutes with
  180 REM it out, the module's interrupt handler is the cause and the Tube is
  190 REM only the thing that exposes it - which is a fixable position. If it
  200 REM dies at 24s anyway the Tube itself is broken at this rate and the
  210 REM module is cleared.
  220 REM
  230 REM Two INKEY(0) per nap, matching 0822j exactly.
  232 REM
  234 REM TIME goes in the heartbeat so the run TIMES ITSELF - the first
  236 REM version did not, and its 97475 counts could not be compared with
  238 REM 0822j's 24 seconds without knowing naps per second. Reading TIME
  240 REM once per 25 naps against 50 INKEYs per 25 naps is 2 per cent more
  242 REM R2 traffic, which is worth paying to get a number that compares.
  244 REM t0% is read once before the loop, so elapsed is centiseconds.
  246 c%=0:t0%=TIME
  250 REPEAT
  260   FOR i%=1 TO 20000:NEXT
  270   j%=INKEY(0):j%=INKEY(0)
  280   c%=c%+1
  290   IF c% MOD 25=0 THEN e%=TIME-t0%+1:PRINT c%;" cs=";e%;" nps=";c%*100/e%
  300 UNTIL FALSE
