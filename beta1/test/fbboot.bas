   10 REM > FBBOOT - capture everything needed to automate the startup
   20 REM
   30 REM   mount the share by hand first, then:
   40 REM       NEW  then  *EXEC FBBOOT  then  RUN
   50 REM
   60 REM Reads only. Changes nothing.
   70 REM
   80 REM Three things are missing before the boot can be set up, and one
   90 REM run answers all three.
  100 REM
  110 REM 1. ROM NUMBERS. On the Master, CMOS byte 5 holds the "default
  120 REM    filing system ROM number" in its low nibble and the "default
  130 REM    language ROM number" in its high nibble - both are ROM
  140 REM    numbers, not filing system ids, which is why *CONFIGURE FILE
  150 REM    9 selects DFS (DFS is ROM 9). So *CONFIGURE FILE and LANG
  160 REM    need the numbers *ROMS reports on THIS machine, and LANMANFS
  170 REM    can be the boot filing system even though its filing system
  180 REM    id, 102, would never fit in a nibble.
  190 REM
  200 REM 2. Choices:Internet.Startup - the network module's OWN
  210 REM    configuration file. It has four sections: interface, network,
  220 REM    CIFS (defaults that let *MOUNT be used in shorthand) and
  230 REM    Hosts (a name table consulted BEFORE the DNS). Nobody has
  240 REM    ever looked at it. It lives in the module, so unlike the
  250 REM    Beeb's CMOS it has survived every power cycle of this project.
  260 REM    A "deskbox" entry in Hosts would make \\deskbox\beeb work
  270 REM    whether or not the router's DNS knows the name.
  280 REM
  290 REM 3. Whether anything in the module can mount without being asked.
  300 REM    A !BOOT on the share cannot: the manual says "the only valid
  310 REM    boot option for shared discs is zero (off)".
  320 :
  330 rf$="RESBOOT"
  334 REM Plain *HELP is not in the list: *ROMS already names every ROM,
  336 REM and under b-em the capture stopped dead in the middle of *HELP's
  338 REM output twice. Unexplained, and not worth explaining - the two
  339 REM targeted *HELPs give the versions that matter.
  340 n%=6
  350 DIM cmd$(n%)
  360 cmd$(1)="ROMS":cmd$(2)="STATUS":cmd$(3)="HELP LANMANFS"
  370 cmd$(4)="HELP LANMANAGER":cmd$(5)="EMINFO"
  380 REM The module's own settings file. *TYPE may not reach the
  390 REM Choices: path - if this one fails, the manual's route is
  400 REM *EDIT Choices:Internet.Startup, which needs a person at the
  410 REM keyboard and F3-COPY-RETURN to leave it.
  420 cmd$(6)="TYPE Choices:Internet.Startup"
  430 PRINT "spooling to ";rf$
  440 OSCLI("SPOOL "+rf$)
  450 i%=1
  460 REM BASIC IV has no ON ERROR LOCAL, so one handler serves the whole
  470 REM list: note the failure, step past the command that caused it and
  480 REM carry on. One unsupported command must not cost the capture.
  490 ON ERROR PRINT "(failed: ";ERR;")":i%=i%+1:GOTO 500
  500 IF i%>n% THEN 550
  510 PRINT "== ";cmd$(i%);" =="
  520 OSCLI(cmd$(i%))
  530 i%=i%+1
  540 GOTO 500
  550 PRINT "== END =="
  560 ON ERROR OFF
  570 OSCLI("SPOOL")
  580 PRINT
  590 PRINT "FBBOOT done - ";rf$;" is on the share."
  600 END
