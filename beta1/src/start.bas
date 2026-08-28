   10 REM > START - the games menu for the GAMES directory
   20 REM
   30 REM   *DIR GAMES   then   CHAIN "START"
   40 REM
   50 REM Host only, Tube off, and it says so if a co-processor is active.
   60 REM
   70 REM IT MOVES ITSELF TO &6500 AND RE-CHAINS. That is the whole trick.
   80 REM ARCADE loads at &1900 and is &4C00 long, so it lands on &1900 to
   90 REM &64FF - straight over a BASIC program at a normal PAGE, INCLUDING
  100 REM the line holding the CALL that comes next. docs/ssd-to-beeb.md
  110 REM meets that by insisting on one immediate-mode line, where the
  120 REM text lives in the input buffer instead. A menu cannot do that, so
  130 REM it gets out of the way instead: above &64FF, below MODE 7's HIMEM
  140 REM of &7C00, which leaves 5888 bytes. SNAPPER and LOADER do the same
  150 REM thing for the same reason - they set PAGE=&4000 before chaining
  160 REM SNAP1, because SNAP2 loads at &1900 and reaches &3F23.
  170 REM
  180 REM Games are declared in the DATA at 9000, one line each:
  190 REM
  200 REM   name , kind , file , load , exec        both in hex
  210 REM   kind 1  CHAIN the named file - the disc's own loader.
  220 REM           <load> is the PAGE to set first, or 0 to leave it.
  222 REM   kind 2  *LOAD it at <load> then CALL <exec>
  224 REM
  225 REM A kind 1 loader needs a PAGE of its own when it cannot live at
  226 REM &6500: CHUCKIE runs MODE 5, whose HIMEM is &5800, so it must sit
  227 REM lower - and above &37FF, where its own CH_EGG lands. &3800 is
  228 REM the only window. The others use MODE 7 and are content at &6500.
  230 REM
  240 REM Only games whose file is actually present are listed, so the menu
  250 REM tells the truth about the directory rather than about the table.
  260 :
  270 me$="START":relo%=&6500:max%=20
  280 IF HIMEM>&8000 THEN PROCcopro:END
  290 MODE 7
  300 IF PAGE<>relo% THEN PAGE=relo%:CHAIN me$
  301 REM *KEY 10 IS the BREAK key, so BREAK means "back to the menu" -
  302 REM the key that matters, because a game ends by being broken out of
  303 REM and Arcadians has done *TAPE by then. f1 gets the SAME string as
  304 REM a fallback: key 10 needs no keypress and f1 does, but a key that
  305 REM works beats one that does not, and having both is how to tell
  306 REM which is which. Definitions survive a soft BREAK ("preserved
  307 REM other than following a hard break") but the current directory
  308 REM does not, hence the *DIR. CTRL-BREAK clears both.
  309 k$="*DIR GAMES|MCHAIN""START""|M":OSCLI("KEY 10 "+k$):OSCLI("KEY 1 "+k$)
  310 DIM nm$(max%),ki%(max%),fi$(max%),ld%(max%),ex%(max%)
  320 DIM nb% 31,blk% 17
  330 n%=0
  340 RESTORE 9000
  350 READ a$
  360 IF a$="END" THEN 400
  370 READ k%,f$,l$,e$
  380 IF FNhere(f$) THEN PROCadd(a$,k%,f$,l$,e$)
  390 GOTO 350
  400 IF n%=0 THEN PRINT'"No games found in this directory.":PRINT"Is the current directory GAMES?":END
  410 c%=FNask
  420 IF c%=0 THEN PRINT:END
  430 REM THE LAUNCH RUNS AT TOP LEVEL, and must. MODE is illegal with
  440 REM anything on the BASIC stack: inside a PROC or FN it is "Bad
  450 REM MODE", error 25, EVEN WHEN the mode asked for is the one already
  460 REM selected and HIMEM does not move. Reproduced under b-em on
  470 REM 2026-08-22 after it happened on the machine at the CALL's own
  480 REM MODE line. Nothing may be printed between the load and the call
  490 REM either - the cursor and any scroll would write into the file
  500 REM that has just been loaded.
  505 IF ki%(c%)=1 AND ld%(c%)>0 THEN PAGE=ld%(c%)
  510 IF ki%(c%)=1 THEN CHAIN fi$(c%)
  520 MODE 7
  530 OSCLI("LOAD "+fi$(c%)+" "+STR$~ld%(c%))
  540 CALL ex%(c%)
  550 END
  560 :
 1000 REM Returns the choice, 0 to quit. A FUNCTION, so the stack is
 1010 REM clear again by the time the launch runs - see 430.
 1012 REM
 1014 REM *FX4,1 makes the cursor keys return codes instead of editing the
 1016 REM screen: &88 left, &89 right, &8A down, &8B up. It MUST be put
 1018 REM back to 0 before a game starts - Meteors sets it itself, and one
 1020 REM that does not would find its cursor keys editing the display.
 1022 REM
 1024 REM Only the marker is redrawn, never the list. Reprinting five lines
 1026 REM per keypress flickers, and in MODE 7 it would also have to
 1028 REM rewrite the colour control code that sits in column 2.
 1030 DEF FNask
 1032 LOCAL i%,k%,sel%,r0%
 1033 REM Cursor off. It sits on the marker cell and flashes there, which
 1034 REM on a menu reads as the marker itself flickering.
 1035 VDU 23,1,0;0;0;0;
 1036 PRINT
 1037 REM Both rows of a double-height line must be identical, so the whole
 1038 REM line including "Q to Quit" is printed twice. 33 of the 40 columns:
 1039 REM two control codes, 21 characters of title, one more code, nine.
 1040 PRINT CHR$141;CHR$131;"  BBC Master games   ";CHR$134;"Q to Quit"
 1041 PRINT CHR$141;CHR$131;"  BBC Master games   ";CHR$134;"Q to Quit"
 1042 PRINT
 1043 r0%=VPOS
 1044 FOR i%=1 TO n%
 1046   PRINT "  ";CHR$131;nm$(i%)
 1048 NEXT
 1056 sel%=1
 1058 *FX4,1
 1060 REPEAT
 1062   PRINT TAB(1,r0%+sel%-1);"*";
 1064   k%=GET
 1066   PRINT TAB(1,r0%+sel%-1);" ";
 1068   IF k%=&8B THEN sel%=sel%-1
 1070   IF k%=&8A THEN sel%=sel%+1
 1072   IF k%>ASC"0" AND k%<=ASC"0"+n% THEN sel%=k%-ASC"0":k%=13
 1074   IF sel%<1 THEN sel%=n%
 1076   IF sel%>n% THEN sel%=1
 1078 UNTIL k%=13 OR k%=ASC"Q" OR k%=ASC"q" OR k%=ASC"0"
 1080 *FX4,0
 1082 PRINT TAB(0,r0%+n%+1);
 1083 REM The cursor comes back on the way out to BASIC. A game will set
 1084 REM whatever it wants; a person at a prompt needs to see it.
 1085 IF k%<>13 THEN VDU 23,1,1;0;0;0;:=0
 1086 =sel%
 1180 :
 1300 DEF PROCadd(a$,k%,f$,l$,e$)
 1310 n%=n%+1
 1320 nm$(n%)=a$:ki%(n%)=k%:fi$(n%)=f$
 1330 ld%(n%)=EVAL("&"+l$):ex%(n%)=EVAL("&"+e$)
 1340 ENDPROC
 1350 :
 1360 REM OSFile A=5, read catalogue information: 0 back means no such
 1370 REM object. It is the only way to ask - *CAT prints, it does not
 1380 REM answer.
 1390 DEF FNhere(f$)
 1400 $nb%=f$
 1410 blk%!0=nb%
 1420 A%=5:X%=blk% AND 255:Y%=blk% DIV 256
 1430 =(USR(&FFDD) AND &FF)<>0
 1440 :
 1450 DEF PROCcopro
 1460 PRINT'"A co-processor is active."
 1470 PRINT"These games are 6502 programs that poke the"
 1480 PRINT"screen and the hardware directly, so they must"
 1490 PRINT"run on the HOST."
 1500 PRINT'"  *CONFIGURE NoTube    then CTRL-BREAK"
 1510 ENDPROC
 1520 :
 9000 DATA Arcadians,2,ARCADE,1900,3F00
 9010 DATA Chuckie Egg,1,CHUCKIE,3800,0
 9020 DATA Donkey Kong,1,DONKEY,0,0
 9030 DATA Meteors,1,METEORS,0,0
 9040 DATA Snapper,1,LOADER,0,0
 9050 DATA END,0,0,0,0
