   10 REM > FBSETTH - set the real-time clock, ON THE HOST
   20 REM
   30 REM   co-processor off:  NEW   then  *EXEC FBSETTH   then  RUN
   40 REM
   50 REM The co-processor version failed with error 16 at the SYS. The
   60 REM tokenising was byte-identical in shape to PTERM's working
   70 REM SYS "OS_Word",&C0,blk%, differing only in the reason code, so it
   80 REM is ARM Tube OS rejecting OSWORD &0F rather than anything wrong
   90 REM with the source - and 16 there is an OS error passed through,
  100 REM not BASIC's "Syntax error".
  110 REM
  120 REM Which is fair enough: the RTC is HOST hardware. Reaching it
  130 REM across the Tube buys nothing, so do it on the host where OSWORD
  140 REM &0F is a plain call.
  150 REM
  160 REM Why bother: on a Master the CMOS and the clock are one chip, and
  170 REM RESCMOS shows that chip is holding nothing - every setting zero
  180 REM or Unset, both Internal Tube AND No Tube, a date of year 197B at
  190 REM hour F3. A flat battery leaves its CONTROL registers undefined as
  200 REM well as its time, and a free-running unclaimed IRQ from it would
  210 REM fit the one asymmetry measured all day: stable on the host, dead
  220 REM inside five minutes on the co-processor.
  230 REM
  240 REM Writing a valid time rewrites those registers.
  250 :
  260 t$="Fri,21 Aug 2026.15:30:00"
  270 ON ERROR PROCerr:END
  280 DIM blk% 31
  290 PRINT "before:"
  300 OSCLI("TIME")
  310 PRINT "writing type 8:"
  320 PROCset(8,t$)
  330 OSCLI("TIME")
  340 PRINT "writing type 0:"
  350 PROCset(0,t$)
  360 OSCLI("TIME")
  370 PRINT
  380 PRINT "If either reads back 2026 the clock chip has been rewritten."
  390 END
  400 :
 1000 DEF PROCset(ty%,s$)
 1010 LOCAL i%
 1020 FOR i%=0 TO 31:blk%?i%=0:NEXT
 1030 blk%?0=ty%
 1040 FOR i%=1 TO LEN(s$):blk%?i%=ASC(MID$(s$,i%,1)):NEXT
 1050 blk%?(LEN(s$)+1)=13
 1060 A%=&0F:X%=blk% AND 255:Y%=blk% DIV 256
 1070 CALL &FFF1
 1080 ENDPROC
 1090 :
 1100 DEF PROCerr
 1110 PRINT:PRINT "Error ";ERR;" at line ";ERL
 1120 REPORT:PRINT
 1130 ENDPROC
