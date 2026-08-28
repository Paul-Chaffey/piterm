   10 REM > FBDNS - why the resolver answers *PING but not PTERM
   20 REM
   30 REM   *EXEC FBDNS  then  RUN        copro 15, *ARMBASIC, tube on
   40 REM
   50 REM *PING server resolves on the machine and PTERM says the name is in
   60 REM neither HOSTS nor DNS. Every name PTERM has ever resolved was in
   70 REM HOSTS - deskbox, beeb, archbox - so there is no evidence its DNS path
   80 REM has EVER worked, and the fault is unlikely to be about server.
   90 REM
  100 REM This asks the same question several ways and writes everything to
  110 REM RESDNS, because the useful answer is which of them differ:
  120 REM
  130 REM   the name NUL-terminated, which is what PTERM sends
  140 REM   the name CR-terminated, which is what a BBC ROM usually expects
  150 REM   bare, and with .lan on the end
  160 REM   a name already known to work from HOSTS, as a control
  170 REM
  180 REM AND IT DUMPS THE RAW BYTES rather than trusting the layout.
  190 REM specification.md 4 records that the published table is WRONG for the
  200 REM resolver and cost a run; PTERM reads +20 as a pointer to a list of
  210 REM 16-bit pointers, and if that assumption is also wrong the derived
  220 REM answer would look like "empty list" no matter what came back.
  230 :
  240 ON ERROR PROCbad:END
  250 DIM blk% 31, nm% 255, pk% 7, ob% 4095
  260 op%=0
  270 PROCsay("[fbdns]")
  280 PROCtry("server",0,"NUL")
  290 PROCtry("server",13,"CR")
  300 PROCtry("server.lan",0,"NUL")
  310 PROCtry("server.lan",13,"CR")
  320 PROCtry("archbox",0,"NUL")
  330 PROCtry("archbox.lan",0,"NUL")
  340 PROCtry("deskbox",0,"NUL")
  350 PROCsave
  360 PRINT "written to RESDNS"
  370 END
  380 :
  390 DEF PROCtry(n$,t%,w$)
  400 LOCAL i%,lp%
  410 PROCsay("")
  420 PROCsay("name="+n$+" term="+w$)
  430 FOR i%=1 TO LEN(n$):nm%?(i%-1)=ASC(MID$(n$,i%,1)):NEXT
  440 nm%?LEN(n$)=t%
  450 FOR i%=0 TO 27:blk%?i%=0:NEXT
  460 blk%?0=28:blk%?1=28:blk%?2=&40:blk%!8=nm%
  470 SYS "OS_Word",&C0,blk%
  480 PROCsay("  cmd="+STR$(blk%?2)+" result="+STR$(blk%?3))
  490 PROCsay("  +12 type="+STR$(blk%!12)+"  +16 len="+STR$(blk%!16))
  500 lp%=blk%!20
  510 PROCsay("  +20 list=&"+STR$~lp%+"  +24=&"+STR$~(blk%!24))
  520 IF blk%?3<>0 THEN PROCsay("  resolver refused, nothing to follow"):ENDPROC
  530 IF lp%=0 THEN PROCsay("  list pointer is zero"):ENDPROC
  540 PROCdump("  list  ",lp%,16)
  550 PROCfollow(lp%)
  560 ENDPROC
  570 :
  580 REM Sixteen bytes of host memory, as bytes and as words, so the shape of
  590 REM the list can be READ rather than assumed. If the entries are 32-bit
  600 REM the words column is the answer; if 16-bit, the bytes column is.
  610 DEF PROCdump(l$,a%,n%)
  620 LOCAL i%,s$,v%
  630 s$=""
  640 FOR i%=0 TO n%-1
  650   v%=FNpeek(a%+i%)
  660   s$=s$+RIGHT$("0"+STR$~v%,2)+" "
  670 NEXT
  680 PROCsay(l$+"&"+STR$~a%+": "+s$)
  690 ENDPROC
  700 :
  710 REM Both readings of the first entry, and the four bytes each points at.
  720 DEF PROCfollow(lp%)
  730 LOCAL p16%,p32%,i%,s$
  740 p16%=FNpeek(lp%)+FNpeek(lp%+1)*256
  750 p32%=p16%+FNpeek(lp%+2)*65536+FNpeek(lp%+3)*16777216
  760 PROCsay("  first entry as 16-bit &"+STR$~p16%+"  as 32-bit &"+STR$~p32%)
  770 IF p16%<>0 THEN PROCdump("  at16 ",p16%,4)
  780 IF p32%<>0 AND p32%<>p16% THEN PROCdump("  at32 ",p32%,4)
  790 s$="  as an address: "
  800 IF p16%<>0 THEN s$=s$+STR$(FNpeek(p16%))+"."+STR$(FNpeek(p16%+1))+"."+STR$(FNpeek(p16%+2))+"."+STR$(FNpeek(p16%+3))
  810 PROCsay(s$)
  820 ENDPROC
  830 :
  840 DEF FNpeek(a%)
  850 !pk%=a%
  860 SYS "OS_Word",5,pk%
  870 =pk%?4
  880 :
  890 REM Buffered and saved once. A BPUT per character over LANManFS is 58ms.
  900 DEF PROCsay(s$)
  910 LOCAL i%
  920 PRINT s$
  930 FOR i%=1 TO LEN(s$)
  940   IF op%<4090 THEN ob%?op%=ASC(MID$(s$,i%,1)):op%=op%+1
  950 NEXT
  960 IF op%<4090 THEN ob%?op%=13:ob%?(op%+1)=10:op%=op%+2
  970 ENDPROC
  980 :
  990 DEF PROCsave
 1000 IF op%>0 THEN OSCLI("SAVE RESDNS "+STR$~ob%+" +"+STR$~op%)
 1010 ENDPROC
 1020 :
 1030 DEF PROCbad
 1040 PRINT "error ";ERR;" at line ";ERL
 1050 REPORT:PRINT
 1060 PROCsave
 1070 ENDPROC
