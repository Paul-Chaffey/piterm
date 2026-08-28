   10 REM > FBSIT - does the machine survive doing nothing at all?
   15 REM
   20 REM   CHAIN "FBSIT"      pure computation, no TIME, no files, no net
   25 REM   CHAIN "FBSITT"     the same, but reading TIME every pass
   30 REM
   35 REM FBIDLE0 crashed. It never connected, never polled, never touched
   40 REM a socket - it looped on a nap and wrote a heartbeat every three
   45 REM seconds. So the fault is not the module, not polling, not the
   50 REM assembled move, not the scroll and not PTERM. All of that was
   55 REM innocent and was debugged anyway.
   60 REM
   65 REM Two things in that loop still crossed the Tube: TIME, which on a
   70 REM co-processor is read from the host, and the file write. This
   75 REM removes both. It counts, and it prints one character roughly
   80 REM every second so the screen shows it is alive - that print is the
   85 REM only OS call in the loop.
   90 REM
   95 REM   FBSIT survives, FBSITT crashes -> TIME across the Tube
  100 REM   both crash                     -> the machine itself, and no
  105 REM                                     amount of BASIC will fix it
  110 REM   both survive                   -> it is the file write, ie
  115 REM                                     LANManFS, and the profiler
  120 REM                                     was causing what it measured
  125 REM
  130 REM Leave it ten minutes. FBIDLE0 died well inside five. Count the
  135 REM dots: fifty to a line, so each full line is about a minute.
  140 :
  145 usetime%=FALSE
  150 usefile%=FALSE
  155 usenap%=FALSE
  160 spin%=1200:wevery%=50:wf$="RESSIT"
  165 :
  170 c%=0:l%=0:t=0
  175 PRINT "FBSIT - one dot a second, 50 to a line. usetime=";usetime%
  180 REPEAT
  185   FOR i%=1 TO spin%:NEXT
  190   IF usenap% THEN PROCnap
  195   IF usetime% THEN t=TIME
  200   c%=c%+1
  205   VDU 46
  210   IF usefile% AND (c% MOD wevery%)=0 THEN PROCwrite
  215   IF (c% MOD 50)=0 THEN PRINT " ";c%
  220 UNTIL FALSE
  225 END
  230 :
  235 REM Open, append one line, close - exactly what the profiler and the
  240 REM PGRID dump do, and the only other thing FBIDLE0 was doing when it
  245 REM died. No TIME anywhere in here.
  250 REM PTERM's nap, verbatim. This is NOT what usetime% tests: that
  255 REM reads TIME once a pass with 1200 loop iterations between, while
  260 REM this spins on TIME until the tick changes - thousands of reads a
  265 REM tick, every one of them crossing the Tube to the host. FBIDLE0
  270 REM ran this on every pass.
  275 DEF PROCnap
  280 LOCAL t
  285 t=TIME
  290 REPEAT UNTIL TIME<>t
  295 ENDPROC
  300 :
  305 DEF PROCwrite
  310 LOCAL h%,s$,i%
  315 s$="c="+STR$(c%)
  320 h%=OPENUP(wf$)
  325 IF h%=0 THEN h%=OPENOUT(wf$)
  330 IF h%=0 THEN ENDPROC
  335 PTR#h%=EXT#h%
  340 FOR i%=1 TO LEN(s$):BPUT#h%,ASC(MID$(s$,i%,1)):NEXT
  345 BPUT#h%,13:BPUT#h%,10
  350 CLOSE#h%
  355 ENDPROC
