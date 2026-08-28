   10 REM > BEEBLINK - development command channel over TCP
   20 REM Type this in once on the real Master, then RUN.
   30 REM It connects OUT to the listener and executes what arrives:
   40 REM    *cmd   run as OSCLI          $expr  string EVAL
   50 REM    expr   numeric EVAL          ESCAPE quits
   60 REM Development tool. Plaintext, LAN only, executes what it is sent.
   70 ip$="192.0.2.10":pt%=6502
   80 DIM b% 31,a% 31,r% 255,t% 255
   85 k%=0:l$=""
   90 ON ERROR PROCerr:END
  100 PROCzero:b%?2=0:b%!4=2:b%!8=1:PROCosw
  110 PRINT "creat   r=";~b%?3;" sock=";b%!4
  120 IF b%!4=-1 OR b%?3<>0 THEN PRINT "creat failed":END
  140 k%=b%!4
  150 PROCzero:b%?2=&12:b%!4=k%:b%!8=&8004667E:!r%=1:b%!12=r%:PROCosw
  160 PRINT "ioctl   r=";~b%?3
  170 PROCaddr
  180 PROCzero:b%?2=4:b%!4=k%:b%!8=a%:b%!12=16:PROCosw
  190 PRINT "connect r=";~b%?3
  200 IF b%?3<>0 THEN END
  210 PRINT "linked to ";ip$;":";pt%;"  ESCAPE quits"
  220 l$=""
  230 *FX229,1
  240 PROCsend("BEEBLINK ready")
  250 ON ERROR PROCerr:GOTO 260
  260 REPEAT:PROCpoll:UNTIL INKEY(0)=27
  270 *FX229,0
  280 PROCzero:b%?2=&10:b%!4=k%:PROCosw
  290 PRINT "closed."
  300 END
  310 :
  320 DEF PROCpoll
  330 LOCAL n%,i%,c%
  335 REM ONE byte per call. Socket_Recv blocks until the requested
  336 REM count is FULLY satisfied - asking for 255 when 4 are in
  337 REM flight hangs forever. See specification.md 5.5a.
  338 REM Flags 8 = MSG_DONTWAIT; error &1E means "nothing available".
  340 PROCzero:b%?0=20:b%?1=8:b%?2=5:b%!4=k%:b%!8=r%:b%!12=1:b%!16=8:PROCosw
  350 n%=b%!4
  360 IF n%<1 THEN ENDPROC
  370 FOR i%=0 TO n%-1
  380   c%=r%?i%
  390   IF c%>31 THEN l$=l$+CHR$c%
  400   IF c%=13 THEN PROCdo:l$=""
  410 NEXT
  420 ENDPROC
  430 :
  440 DEF PROCdo
  450 IF l$="" THEN ENDPROC
  460 PRINT ">";l$
  470 IF LEFT$(l$,1)="*" THEN OSCLI MID$(l$,2):PROCsend("ok"):ENDPROC
  480 IF LEFT$(l$,1)="$" THEN PROCsend(EVAL(MID$(l$,2))):ENDPROC
  490 PROCsend(STR$(EVAL(l$)))
  500 ENDPROC
  510 :
  520 DEF PROCsend(s$)
  530 LOCAL i%,n%
  540 s$=s$+CHR$13+CHR$10
  550 n%=LEN(s$)
  560 FOR i%=1 TO n%:t%?(i%-1)=ASC(MID$(s$,i%,1)):NEXT
  570 PROCzero:b%?2=8:b%!4=k%:b%!8=t%:b%!12=n%:PROCosw
  580 ENDPROC
  590 :
  600 DEF PROCaddr
  610 LOCAL i%,p%,q%,o%
  620 FOR i%=0 TO 15:a%?i%=0:NEXT
  630 a%?0=16:a%?1=2
  640 a%?2=pt% DIV 256:a%?3=pt% MOD 256
  650 p%=1:o%=4
  660 FOR i%=1 TO 4
  670   q%=INSTR(ip$+".",".",p%)
  680   a%?o%=VAL(MID$(ip$,p%,q%-p%))
  690   p%=q%+1:o%=o%+1
  700 NEXT
  710 ENDPROC
  720 :
  730 DEF PROCzero
  740 LOCAL i%
  750 FOR i%=0 TO 27:b%?i%=0:NEXT
  760 b%?0=28:b%?1=28:b%?3=0
  770 ENDPROC
  780 :
  790 DEF PROCosw
  800 LOCAL A%,X%,Y%
  810 A%=&C0:X%=b% MOD 256:Y%=b% DIV 256
  820 CALL &FFF1
  830 ENDPROC
  840 :
  850 DEF PROCerr
  860 *FX229,0
  861 *FX4,0
  865 l$=""
  870 PRINT:PRINT "Error ";ERR;" at line ";ERL
  875 REPORT:PRINT
  880 IF k%>0 THEN PROCsend("ERR "+STR$(ERR)+" line "+STR$(ERL))
  890 ENDPROC
