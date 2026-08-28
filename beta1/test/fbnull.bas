   10 REM > FBNULL - is the 3.2ms call the MODULE, or is it BASIC?
   20 REM
   30 REM   CHAIN "FBNULL"     copro 15, *ARMBASIC, tube on
   40 REM   socat TCP-LISTEN:2324,reuseaddr,fork EXEC:<repo>/tools/quiet.sh
   50 REM
   60 REM FBHOST settled the ROM question and then raised a better one.
   70 REM
   80 REM The host polls at 49,400us a call against the co-processor's
   90 REM 3,200 - fifteen times slower WITH no Tube in the path at all. A
  100 REM sideways ROM runs on that side, so it would be moving work onto
  110 REM the slower machine. That is a no, measured rather than argued.
  120 REM
  130 REM But 49ms is far too slow to be an OSWORD. It is the INTERPRETER:
  140 REM FNtake runs a 28-iteration zeroing loop and a dozen statements
  150 REM before it ever reaches the call. Which makes the co-processor's
  160 REM 3.2ms suspect in exactly the same way.
  170 REM
  180 REM Everything concluded so far - that the module meters data out 64
  190 REM bytes at a time, that 95% of calls find nothing, that ~2.4KB/sec
  200 REM is the ceiling of this hardware - assumed that 3.2ms was the
  210 REM module. If most of it is ARM BASIC interpreting the wrapper, the
  220 REM ceiling is not the hardware and the fix is a faster caller.
  230 REM
  240 REM Three timings over the same loop, on a socket with no data so the
  250 REM call is its cheapest:
  260 REM
  270 REM   full   the whole of FNtake, OSWORD and all
  280 REM   noosw  identical, but the OSWORD is not made
  290 REM   bare   FOR/NEXT and nothing else
  300 REM
  310 REM full minus noosw is the call. noosw minus bare is the wrapper.
  320 REM Whichever of those two is the larger is what to attack.
  330 :
  340 host$="192.0.2.10":port%=2324
  350 rf$="RESNULL"
  360 mnowait%=8
  370 reps%=1000
  380 :
  390 rf%=0:sock%=-1:err%=0:doit%=TRUE
  400 ON ERROR PROCerr:END
  410 DIM blk% 31, sa% 31, rx% 127
  420 PROCopen
  430 PROCw("[fbnull1]")
  440 PROCw("run="+STR$(TIME)+" reps="+STR$(reps%))
  450 PROCconnect
  460 :
  470 doit%=TRUE:PROCtime("full")
  480 doit%=FALSE:PROCtime("noosw")
  490 PROCbare
  500 :
  510 PROCw("[end]")
  520 PROCshut
  530 PROCclose
  540 PRINT "FBNULL done - ";rf$;" is on the share."
  550 END
  560 :
 1000 DEF PROCtime(tag$)
 1010 LOCAL i%,g%,t,c
 1020 t=TIME
 1030 FOR i%=1 TO reps%
 1040   g%=FNtake(64)
 1050 NEXT
 1060 c=TIME-t
 1070 IF c<1 THEN c=1
 1080 PROCw(tag$+" calls="+STR$(reps%)+" cs="+STR$(c)+" us_per_call="+STR$(c*10000 DIV reps%))
 1090 ENDPROC
 1100 :
 1110 REM The loop with nothing in it, so the FOR/NEXT itself is accounted
 1120 REM for and not silently charged to the call.
 1130 DEF PROCbare
 1140 LOCAL i%,t,c
 1150 t=TIME
 1160 FOR i%=1 TO reps%
 1170 NEXT
 1180 c=TIME-t
 1190 IF c<1 THEN c=1
 1200 PROCw("bare calls="+STR$(reps%)+" cs="+STR$(c)+" us_per_call="+STR$(c*10000 DIV reps%))
 1210 ENDPROC
 1220 :
 1230 REM Byte for byte what PTERM does, including the zeroing loop, so the
 1240 REM wrapper being measured is the real one and not a tidied version.
 1250 DEF FNtake(n%)
 1260 LOCAL i%
 1270 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1280 blk%?0=20:blk%?1=8:blk%?2=&05
 1290 blk%!4=sock%:blk%!8=rx%:blk%!12=n%:blk%!16=mnowait%
 1300 IF doit% THEN PROCosw
 1310 IF NOT doit% THEN =0
 1320 IF blk%?2<>0 THEN PROCstop("OSWORD C0 unclaimed")
 1330 err%=blk%?3
 1340 IF err%<>0 THEN =-2
 1350 =blk%!4
 1360 :
 1370 DEF PROCosw
 1380 SYS "OS_Word",&C0,blk%
 1390 ENDPROC
 1400 :
 1410 DEF PROCconnect
 1420 LOCAL i%,a%,b%,o%
 1430 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1440 blk%?0=28:blk%?1=28:blk%?2=0:blk%!4=2:blk%!8=1
 1450 PROCosw
 1460 IF blk%?2<>0 OR blk%?3<>0 THEN PROCstop("cannot create a socket")
 1470 sock%=blk%!4
 1480 FOR i%=0 TO 15:sa%?i%=0:NEXT
 1490 sa%?0=16:sa%?1=2
 1500 sa%?2=port% DIV 256:sa%?3=port% MOD 256
 1510 a%=1:o%=4
 1520 FOR i%=1 TO 4
 1530   b%=INSTR(host$+".",".",a%)
 1540   sa%?o%=VAL(MID$(host$,a%,b%-a%))
 1550   a%=b%+1:o%=o%+1
 1560 NEXT
 1570 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1580 blk%?0=28:blk%?1=28:blk%?2=4:blk%!4=sock%:blk%!8=sa%:blk%!12=16
 1590 PROCosw
 1600 IF blk%?3<>0 THEN PROCstop("cannot connect, r=&"+STR$~blk%?3)
 1610 PROCw("connected to "+host$+":"+STR$(port%))
 1620 ENDPROC
 1630 :
 1640 DEF PROCclose
 1650 LOCAL i%
 1660 IF sock%<0 THEN ENDPROC
 1670 FOR i%=0 TO 27:blk%?i%=0:NEXT
 1680 blk%?0=28:blk%?1=28:blk%?2=&10:blk%!4=sock%
 1690 PROCosw
 1700 sock%=-1
 1710 ENDPROC
 1720 :
 1730 DEF PROCopen
 1740 rf%=OPENOUT(rf$)
 1750 ENDPROC
 1760 :
 1770 DEF PROCw(s$)
 1780 LOCAL i%
 1790 IF rf%=0 THEN ENDPROC
 1800 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1810 BPUT#rf%,13:BPUT#rf%,10
 1820 ENDPROC
 1830 :
 1840 DEF PROCshut
 1850 IF rf%<>0 THEN CLOSE#rf%
 1860 rf%=0
 1870 ENDPROC
 1880 :
 1890 DEF PROCstop(s$)
 1900 PROCw("fail="+s$)
 1910 PROCw("[end]")
 1920 PROCshut
 1930 PROCclose
 1940 PRINT "FBNULL: ";s$
 1950 END
 1960 :
 1970 DEF PROCerr
 1980 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 1990 PROCw("[end]")
 2000 PROCshut
 2010 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2020 REPORT:PRINT
 2030 ENDPROC
