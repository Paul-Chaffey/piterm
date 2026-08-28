   10 REM > TUBECRC - count Tube corruptions instead of waiting for a hang
   20 REM
   30 REM   CTRL-BREAK, *ARMBASIC, *MOUNT, *DIR Pi-TERM, CHAIN "TUBECRC"
   40 REM
   50 REM WHY THIS EXISTS. Waiting for the co-processor to freeze measures a
   60 REM single rare event, and transactions-to-failure is geometrically
   70 REM distributed - its standard deviation EQUALS its mean. One run per
   80 REM setting therefore carries about 100% relative error, which is why
   90 REM three 65C102 runs gave 51,550, 52,000 and 79,900 under conditions
  100 REM that were meant to be identical. That spread was not sloppiness.
  110 REM
  120 REM Counting corruptions instead lets one run tally hundreds of events,
  130 REM and precision goes as 1/SQR(events) - 100 errors is 10%. Same
  140 REM wall-clock, an order of magnitude better resolution, and the run
  150 REM SURVIVES an error instead of ending on it.
  160 REM
  170 REM TUBEDATA is 64K of fixed pseudo-random bytes from
  180 REM tools/mktubedata.py, with its byte sum baked in below. It is not a
  190 REM program and mirror.sh never rewrites it, so the reference stays
  200 REM valid across every run and every sweep point. Regenerate it only by
  210 REM re-running that script, and then this number must change with it.
  220 REM
  230 REM The load crosses the Tube by the bulk transfer path. It also
  240 REM crosses the network, and LANManFS is NOT innocent here - but TCP
  250 REM and SMB both checksum and the Tube does not, so a mismatch is far
  260 REM more likely to be the Tube. That is not airtight. Say so in any
  270 REM write-up rather than discovering it later.
  280 :
  290 REM IT ASKS for tube_delay because nothing can read it back: no *
  300 REM command exposes it and it is handed to the VideoCore at boot. A run
  310 REM that cannot state its own conditions has cost this project four
  320 REM separate wrong conclusions in one day, so the number is typed in
  330 REM and printed on every progress line.
  340 :
  350 bld$="0823a"
  360 f$="TUBEDATA":siz%=65536:ref%=8345686
  370 reps%=200:every%=10
  380 :
  390 PRINT "TUBECRC build ";bld$
  400 PRINT "file=";f$;" bytes=";siz%;" ref sum=";ref%
  410 PRINT "passes=";reps%;"  progress every ";every%
  420 PRINT
  430 INPUT "tube_delay for this run ",td%
  440 PRINT "MODE 7 on the host. Note whether the Pi was cold or hot."
  450 PRINT
  460 :
  470 DIM buf% siz%
  480 n%=0:bad%=0:t0%=TIME
  490 :
  500 REPEAT
  510   REM Sentinels first, so a short or skipped load cannot checksum clean
  520   REM off the previous pass's bytes.
  530   buf%?0=0:buf%?(siz%-1)=0
  540   OSCLI("LOAD "+f$+" "+STR$~buf%)
  550   s%=0
  560   FOR i%=0 TO siz%-1:s%=s%+buf%?i%:NEXT
  570   n%=n%+1
  580   IF s%<>ref% THEN PROCbad(s%)
  590   IF n% MOD every%=0 THEN PROCsay
  600 UNTIL n%>=reps%
  610 PROCsay
  620 PRINT "DONE td=";td%;" passes=";n%;" bad=";bad%
  630 END
  640 :
  650 DEF PROCbad(g%)
  660 bad%=bad%+1
  670 PRINT "MISMATCH ";bad%;" on pass ";n%;" got ";g%;" want ";ref%
  680 ENDPROC
  690 :
  700 DEF PROCsay
  710 LOCAL e%
  720 e%=TIME-t0%+1
  730 PRINT "td=";td%;" pass=";n%;" bad=";bad%;" MB=";n%*siz%/1048576;" secs=";e%/100
  740 ENDPROC
