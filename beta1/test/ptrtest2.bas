   10 REM > PTRTEST2 - the same OSWORD &C0 call at a LOW and a HIGH address
   20 REM
   30 REM PTRTEST reported ptr_out=NO and that conclusion is not safe: every
   40 REM buffer in that run was above 64K, because it padded with DIM pad%
   50 REM &10000 to make the inward test unambiguous. On a 6502 co-processor
   60 REM every address is necessarily below 64K, which is the condition 5.5c
   70 REM proved pointers under. So the run changed two things at once.
   80 REM
   90 REM This changes one. Identical sockaddr bytes, identical call, twice:
  100 REM once from an address that fits in 16 bits and once from one that
  110 REM does not. If low works and high does not, the pointer is being
  120 REM truncated and we know exactly what a host-side BEEBNET would be for.
  130 REM If BOTH fail, the address was never the issue - look at the listener.
  140 REM
  150 REM Also: &1E is not "refused". 5.5c has it as "cannot satisfy the
  160 REM request", the module's would-block, so connect is retried rather
  170 REM than being read as a hard failure the way PTRTEST read it.
  180 REM
  190 REM COPRO 15 ONLY:  *FX 151,230,15  then CTRL-BREAK  then *ARMBASIC
  200 REM
  210 REM   socat TCP-LISTEN:6502,reuseaddr,fork SYSTEM:'echo PTRTEST-MARKER-42; cat'
  220 :
  230 ip$="192.0.2.10":pt%=6502
  240 rf$="RESPTR2"
  250 :
  260 rf%=0:k%=-1
  270 ON ERROR PROCerr:END
  280 PROCopen
  290 PROCw("[ptrtest2]")
  300 PROCw("run="+STR$(TIME))
  310 :
  320 REM Low first, before anything pads the heap. On copro 15 PAGE is &8F00
  330 REM so these land in &9xxx, and &9xxx on the HOST is the sideways ROM
  340 REM window - if the pointer is not honoured, a stray write there does
  350 REM nothing. That is deliberate.
  360 DIM b% 31, lo_a% 31, lo_r% 255, t% 255
  370 DIM pad% &10000
  380 DIM hi_a% 31, hi_r% 255
  390 :
  400 PROCw("page=&"+STR$~PAGE)
  410 PROCw("block=&"+STR$~b%)
  420 PROCw("lo_sa=&"+STR$~lo_a%+" lo_buf=&"+STR$~lo_r%)
  430 PROCw("hi_sa=&"+STR$~hi_a%+" hi_buf=&"+STR$~hi_r%)
  440 PRINT "low  sockaddr &";~lo_a%;"  buffer &";~lo_r%
  450 PRINT "high sockaddr &";~hi_a%;"  buffer &";~hi_r%
  460 IF lo_a%>=&10000 THEN PROCw("fail=low block is not below 64K"):PROCstop("low block above 64K")
  470 IF hi_a%<&10000 THEN PROCw("fail=high block is not above 64K"):PROCstop("high block below 64K")
  480 :
  490 PROCaddr(lo_a%)
  500 PROCaddr(hi_a%)
  510 :
  520 PRINT
  530 PRINT "--- A: pointer below 64K"
  540 PROCtry("lo",lo_a%,lo_r%)
  550 PRINT
  560 PRINT "--- B: pointer above 64K"
  570 PROCtry("hi",hi_a%,hi_r%)
  580 :
  590 PROCw("[end]")
  600 PROCshut
  610 PRINT
  620 PRINT "PTRTEST2 done - RESPTR2 is on the share"
  630 END
  640 :
  650 REM One full attempt at one address: create, connect, receive, close.
  660 DEF PROCtry(w$,sa%,rb%)
  670 LOCAL i%,got%,ch%,tries%
  680 PROCzero:b%?0=20:b%?1=8:b%?2=0:b%!4=2:b%!8=1:b%!12=0
  690 PROCosw
  700 k%=b%!4
  710 PROCsay(w$+"_creat","+2="+STR$~b%?2+" +3="+STR$~b%?3+" sock="+STR$(k%))
  720 IF b%?2<>0 THEN PROCw("fail=OSWORD C0 unanswered"):ENDPROC
  730 IF b%?3<>0 OR k%<0 THEN PROCw(w$+"_out=CREATFAIL"):ENDPROC
  740 :
  750 REM &1E is would-block, so give connect time to complete rather than
  760 REM calling the first non-zero result a refusal.
  770 tries%=0
  780 REPEAT
  790   PROCzero:b%?0=16:b%?1=8:b%?2=4:b%!4=k%:b%!8=sa%:b%!12=16
  800   PROCosw
  810   tries%=tries%+1
  820   IF b%?3<>0 THEN PROCwait
  830 UNTIL b%?3=0 OR tries%>=20
  840 PROCsay(w$+"_connect","+2="+STR$~b%?2+" +3="+STR$~b%?3+" tries="+STR$(tries%))
  850 IF b%?3<>0 THEN PROCw(w$+"_out=NO"):PROCclose:ENDPROC
  860 PROCw(w$+"_out=YES")
  870 PRINT "  connect OK - the module read ARM memory at this address"
  880 :
  890 FOR i%=0 TO 255:rb%?i%=&55:NEXT
  900 REM One byte per call, ADVANCING the buffer. The first version passed
  910 REM rb% every time, so all sixteen reads landed on byte 0 and only one
  920 REM byte could ever differ from the poison. That still proved the point
  930 REM - byte 0 held &34, the sixteenth character of the marker, which is
  940 REM the byte that was predicted - but it reads like a near miss and it
  950 REM is not what a client would do.
  960 got%=0:T=TIME
  970 REPEAT
  980   PROCzero:b%?0=20:b%?1=8:b%?2=5:b%!4=k%:b%!8=rb%+got%:b%!12=1:b%!16=8
  990   PROCosw
 1000   IF b%?2<>0 THEN got%=-1
 1010   IF b%!4=1 AND got%>=0 THEN got%=got%+1:T=TIME
 1020 UNTIL (TIME-T)>500 OR got%>=16 OR got%<0
 1030 ch%=0
 1040 FOR i%=0 TO 15:IF rb%?i%<>&55 THEN ch%=ch%+1
 1050 NEXT
 1060 PROCsay(w$+"_recv","reported="+STR$(got%)+" changed="+STR$(ch%)+" of 16")
 1070 PROCw(w$+"_buf="+FNhex(rb%,16))
 1080 PROCw(w$+"_txt="+FNtxt(rb%,16))
 1090 IF got%<1 THEN PROCw(w$+"_in=NODATA")
 1100 IF got%>0 AND ch%=0 THEN PROCw(w$+"_in=NO")
 1110 IF got%>0 AND ch%>0 THEN PROCw(w$+"_in=YES")
 1120 IF got%>0 AND ch%>0 THEN PRINT "  *** the module WROTE ARM memory here ***"
 1130 IF got%>0 AND ch%=0 THEN PRINT "  recv claimed data, ARM memory untouched"
 1140 PROCclose
 1150 ENDPROC
 1160 :
 1170 DEF PROCwait
 1180 LOCAL T2
 1190 T2=TIME
 1200 REPEAT UNTIL TIME-T2>10
 1210 ENDPROC
 1220 :
 1230 REM key=value, not "key value" - the analyser partitions at the
 1240 REM first = and a space here made the key "lo_creat +2".
 1250 DEF PROCsay(n$,s$)
 1260 PRINT "  ";n$;"  ";s$
 1270 PROCw(n$+"="+s$)
 1280 ENDPROC
 1290 :
 1300 DEF FNhex(p%,n%)
 1310 LOCAL i%,s$
 1320 s$=""
 1330 FOR i%=0 TO n%-1:s$=s$+RIGHT$("0"+STR$~(p%?i%),2)+" ":NEXT
 1340 =s$
 1350 :
 1360 DEF FNtxt(p%,n%)
 1370 LOCAL i%,s$,c%
 1380 s$=""
 1390 FOR i%=0 TO n%-1
 1400   c%=p%?i%
 1410   IF c%<32 OR c%>126 THEN c%=46
 1420   s$=s$+CHR$(c%)
 1430 NEXT
 1440 =s$
 1450 :
 1460 REM sockaddr_in - confirmed layout, netprogapi.pdf
 1470 DEF PROCaddr(p%)
 1480 LOCAL i%,q%,r%,o%
 1490 FOR i%=0 TO 15:p%?i%=0:NEXT
 1500 p%?0=16:p%?1=2
 1510 p%?2=pt% DIV 256:p%?3=pt% MOD 256
 1520 q%=1:o%=4
 1530 FOR i%=1 TO 4
 1540   r%=INSTR(ip$+".",".",q%)
 1550   p%?o%=VAL(MID$(ip$,q%,r%-q%))
 1560   q%=r%+1:o%=o%+1
 1570 NEXT
 1580 ENDPROC
 1590 :
 1600 DEF PROCclose
 1610 IF k%<0 THEN ENDPROC
 1620 PROCzero:b%?0=8:b%?1=4:b%?2=&10:b%!4=k%
 1630 PROCosw
 1640 k%=-1
 1650 ENDPROC
 1660 :
 1670 DEF PROCzero
 1680 LOCAL i%
 1690 FOR i%=0 TO 27:b%?i%=0:NEXT
 1700 ENDPROC
 1710 :
 1720 DEF PROCosw
 1730 SYS "OS_Word",&C0,b%
 1740 ENDPROC
 1750 :
 1760 DEF PROCopen
 1770 rf%=OPENOUT(rf$)
 1780 ENDPROC
 1790 :
 1800 DEF PROCw(s$)
 1810 LOCAL i%
 1820 IF rf%=0 THEN ENDPROC
 1830 FOR i%=1 TO LEN(s$):BPUT#rf%,ASC(MID$(s$,i%,1)):NEXT
 1840 BPUT#rf%,13:BPUT#rf%,10
 1850 ENDPROC
 1860 :
 1870 DEF PROCshut
 1880 IF rf%<>0 THEN CLOSE#rf%
 1890 rf%=0
 1900 ENDPROC
 1910 :
 1920 DEF PROCstop(s$)
 1930 PROCw("[end]")
 1940 PROCshut
 1950 PRINT "PTRTEST2 stopped: ";s$
 1960 END
 1970 :
 1980 DEF PROCerr
 1990 PRINT:PRINT "Error ";ERR;" at line ";ERL
 2000 REPORT:PRINT
 2010 PROCw("error="+STR$(ERR)+" line="+STR$(ERL))
 2020 PROCw("[end]")
 2030 PROCshut
 2040 ENDPROC
