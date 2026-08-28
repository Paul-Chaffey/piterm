   10 REM > ARMNET - can the ARM co-processor reach OSWORD &C0 at all?
   20 REM
   30 REM specification.md 5.5c says the terminal calls OSWORD &C0 DIRECTLY
   40 REM from the co-processor, because the control block crosses the Tube.
   50 REM That was established with a 6502 co-pro and CALL &FFF1. On ARM
   60 REM there is no CALL &FFF1 - the route is SYS "OS_Word" - and nobody
   70 REM has checked that it arrives.
   80 REM
   90 REM Offline the claimant is SOCKSTUB, which is a FAKE with canned
  100 REM answers, so a success here says the plumbing works and says
  110 REM NOTHING about the real Sprow module.
  120 :
  130 ON ERROR PROCerr:END
  140 what$="start"
  150 DIM b% 31, u% 255
  160 PRINT "block at &";~b%;"  buffer at &";~u%
  170 PRINT
  180 :
  190 what$="OS_Word &C0"
  200 PROCcall(&00,"Socket_Creat ")
  210 PROCcall(&04,"Socket_Connect")
  220 PROCrecv
  230 PROCcall(&10,"Socket_Close ")
  240 :
  250 PRINT
  260 PRINT "[armnetdone]"
  270 END
  280 :
  290 REM +2 holds the command on entry and is ZEROED by a module that
  300 REM services the call. A SURVIVING +2 means nothing claimed it, and
  310 REM then no field is touched at all - +3 reads 0 because it started
  320 REM 0, and an unclaimed call is indistinguishable from success.
  330 REM Socket_Creat is command 0, so a zeroed +2 is indistinguishable
  340 REM from the command byte and proves nothing. A sentinel in +4 does:
  350 REM an unclaimed call touches NO field, so if it comes back changed
  360 REM something serviced the call.
  370 DEF PROCcall(c%,n$)
  380 PROCzero
  390 b%?2=c%:b%!4=&5EEDBEEF
  400 SYS "OS_Word",&C0,b%
  410 PRINT n$;" +2=";~b%?2;" +3=";~b%?3;" +4=&";~b%!4;
  420 IF b%?2=c% AND b%!4=&5EEDBEEF THEN PRINT "   UNCLAIMED" ELSE PRINT "   claimed"
  430 ENDPROC
  440 :
  450 DEF PROCrecv
  460 LOCAL i%,n%
  470 PROCzero
  480 b%?2=&05:b%?0=20:b%?1=8
  490 b%!8=u%:b%!12=1:b%!16=8
  500 u%?0=0
  510 SYS "OS_Word",&C0,b%
  520 n%=b%!4
  530 PRINT "Socket_Recv   +2=";~b%?2;" +3=";~b%?3;" n=";n%;
  540 IF b%?2=&05 THEN PRINT "   UNCLAIMED":ENDPROC
  550 PRINT "   claimed"
  560 REM The pointer at +8 is an ARM address. A host-side 6502 module
  570 REM writing to it is writing to host memory of the same number, so
  580 REM this is the line that says whether a BUFFER crosses the Tube or
  590 REM only the control block does.
  600 PRINT "  first buffer byte = ";~u%?0
  610 ENDPROC
  620 :
  630 DEF PROCzero
  640 LOCAL i%
  650 FOR i%=0 TO 27:b%?i%=0:NEXT
  660 b%?0=28:b%?1=28
  670 ENDPROC
  680 :
  690 DEF PROCerr
  700 PRINT
  710 PRINT "failed during: ";what$
  720 PRINT "error ";ERR;" at line ";ERL
  730 REPORT:PRINT
  740 PRINT "[armnetdone]"
  750 ENDPROC
