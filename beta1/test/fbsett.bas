   10 REM > FBSETT - set the real-time clock, then look at it
   20 REM
   30 REM   CHAIN "FBSETT"     copro 15, *ARMBASIC
   40 REM
   50 REM RESCMOS shows CMOS is not being held: everything zero or Unset,
   60 REM both Internal Tube AND No Tube, and a date reading year 197B at
   70 REM hour F3. The battery is flat.
   80 REM
   90 REM Raw TCP does not care - its timers are relative tick counts, not
  100 REM wall clock - so this is not about the network needing the date.
  110 REM
  120 REM It is about the CHIP. On a Master the CMOS and the real-time
  130 REM clock are the same device, so a flat battery leaves its CONTROL
  140 REM registers undefined too, not merely its time wrong. If the
  150 REM periodic interrupt enable comes up set, it free-runs an IRQ that
  160 REM nothing claims - which the host alone may absorb while the host
  170 REM plus Tube plus module interrupts does not. That is exactly the
  180 REM asymmetry measured today.
  190 REM
  200 REM Writing a valid time rewrites those registers. If the crash goes
  210 REM away afterwards, that is both a cause and a workaround: set the
  220 REM clock once after every power-on.
  230 REM
  240 REM OSWORD &0F, block+0=8, then "Day,DD Mon YYYY.HH:MM:SS".
  250 :
  260 t$="Fri,21 Aug 2026.15:00:00"
  270 ON ERROR PROCerr:END
  280 DIM blk% 31
  282 REM b-em shows no change from either form, but b-em may simply not
  284 REM emulate RTC WRITES - it emulates reads perfectly well. So try
  286 REM both documented block types and print the clock after each; one
  288 REM run on the real machine says which, if either, takes.
  290 PRINT "before:"
  300 OSCLI("TIME")
  305 PRINT "writing type 8 (time and date):"
  310 PROCsettime(8,t$)
  320 OSCLI("TIME")
  325 PRINT "writing type 0 (time and date):"
  330 PROCsettime(0,t$)
  335 OSCLI("TIME")
  340 PRINT
  350 PRINT "If either reads back as 2026 the clock chip has been rewritten."
  360 PRINT "Then run FBIDLE4 again and see whether it still dies."
  370 END
  380 :
 1000 DEF PROCsettime(ty%,s$)
 1010 LOCAL i%
 1020 FOR i%=0 TO 31:blk%?i%=0:NEXT
 1030 blk%?0=ty%
 1040 FOR i%=1 TO LEN(s$)
 1050   blk%?i%=ASC(MID$(s$,i%,1))
 1060 NEXT
 1070 blk%?(LEN(s$)+1)=13
 1080 SYS "OS_Word",&0F,blk%
 1090 ENDPROC
 1100 :
 1110 DEF PROCerr
 1120 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1130 REPORT:PRINT
 1140 ENDPROC
