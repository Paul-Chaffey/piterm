\ ==========================================================================
\ SOCKSTUB - a fake Sprow Ethernet module for offline development
\ ==========================================================================
\ Claims OSWORD &C0 and returns canned responses, so terminal client code
\ can be developed and debugged on an emulator with no hardware present.
\
\ *** THE CONVENTIONS BELOW ARE GUESSES ***
\ The sockaddr layout, the AF_/SOCK_ constants and the location of the
\ return value are undocumented (specification.md section 4). This ROM
\ imitates what we ASSUME the real module does. Passing against SOCKSTUB
\ proves the client is self-consistent - it does NOT prove it will work
\ against real hardware. Correct this ROM once Step 0a reports the truth.
\
\ Build: tools/beebasm -i src/stub.asm
\ Use:   *SRLOAD SOCKSTUB 8000 4    then press BREAK
\ ==========================================================================

CPU 1                           \ 65C12 (Master)

\ ---------------------------------------------------------------- MOS API
OSASCI      = &FFE3
OSNEWL      = &FFE7

\ Service call &08 leaves the original OSWORD registers here.
OSW_A       = &EF               \ the OSWORD number
OSW_X       = &F0               \ control block, low byte
OSW_Y       = &F1               \ control block, high byte

ROMTAB      = &0DF0             \ per-ROM workspace page, indexed by slot

\ &A8-&AF is OS scratch available to paged ROMs during a service call.
blk         = &A8               \ 2 - control block pointer
dst         = &AA               \ 2 - destination buffer
src         = &AC               \ 2 - canned data pointer
ws          = &AE               \ 2 - our workspace pointer

\ NOTE: only &A8-&AF is scratch for paged ROMs. &A0-&A7 belongs to MOS -
\ using it corrupts the OS. Everything below lives in &A8-&AF or in our
\ claimed workspace page:
\   workspace +0 = receive script index
\   workspace +1 = byte count for the current Socket_Recv

\ ==========================================================================
ORG   &8000
GUARD &C000

.rom_start
    BRK                         \ no language entry
    BRK
    BRK
    JMP service_entry
    EQUB &82                    \ service ROM, 6502 code
    EQUB copyright - rom_start
    EQUB 1                      \ binary version
    EQUS "SOCKSTUB", 0
    EQUS "0.01", 0
.copyright
    EQUB 0
    EQUS "(C)2026", 0

\ ==========================================================================
\ Service call dispatch
\ ==========================================================================
.service_entry
    CMP #&01                    \ claim absolute workspace
    BEQ srv_workspace
    CMP #&08                    \ unrecognised OSWORD
    BEQ to_osword
    CMP #&09                    \ *HELP
    BEQ to_help
    RTS

\ Trampolines - the targets are beyond branch range.
.to_osword
    JMP srv_osword
.to_help
    JMP srv_help

\ -------------------------------------------------------------------------
\ Service &01 - claim one page of workspace. Y = first free page on entry;
\ we take it, record it in ROMTAB for our slot, and hand back Y+1.
.srv_workspace
    TYA
    STA ROMTAB, X
    INY
    LDA #1                      \ preserve A, do not claim
    RTS

\ -------------------------------------------------------------------------
.srv_help
    PHA : TXA : PHA : TYA : PHA
    JSR OSNEWL
    LDX #0
.help_loop
    LDA help_text, X
    BEQ help_done
    JSR OSASCI
    INX
    BNE help_loop
.help_done
    PLA : TAY : PLA : TAX : PLA
    RTS

.help_text
    EQUS "SOCKSTUB 0.01 - FAKE socket module", 13
    EQUS "  claims OSWORD &C0 with canned data", 13
    EQUS "  responses are GUESSES, not real", 13, 0

\ -------------------------------------------------------------------------
\ Service &08 - unrecognised OSWORD.
.srv_osword
    LDA OSW_A
    CMP #&C0
    BEQ osw_ours
    LDA #8                      \ not ours, pass on unchanged
    RTS

.osw_ours
    TXA : PHA
    TYA : PHA
    JSR do_socket
    PLA : TAY
    PLA : TAX
    LDA #0                      \ claim the call
    RTS

\ ==========================================================================
\ Socket command dispatch
\ ==========================================================================
.do_socket
    LDA ROMTAB, X               \ X = our slot, still valid on entry
    STA ws+1
    LDA #0
    STA ws

    LDA OSW_X : STA blk
    LDA OSW_Y : STA blk+1

    LDY #2
    LDA (blk), Y                \ command code

    CMP #&00 : BEQ cmd_creat
    CMP #&04 : BEQ cmd_connect
    CMP #&05 : BEQ cmd_recv
    CMP #&08 : BEQ cmd_send
    CMP #&10 : BEQ cmd_ok
    CMP #&12 : BEQ cmd_ok
    CMP #&40 : BEQ cmd_resolve
    BNE cmd_bad

\ -------------------------------------------------------------------------
\ Socket_Creat - hand back a plausible socket number.
.cmd_creat
    LDA #1
    JSR set_return
    JMP ok_result

\ -------------------------------------------------------------------------
\ Socket_Connect - succeed, and rewind the canned receive script.
.cmd_connect
    LDA #0
    LDY #0
    STA (ws), Y                 \ chunk index := 0
    LDY #1
    STA (ws), Y                 \ offset within chunk := 0
    JSR set_return
    JMP ok_result

\ -------------------------------------------------------------------------
\ Socket_Send - claim we sent everything, returning the byte count.
.cmd_send
    LDY #12
    LDA (blk), Y                \ length, low byte
    JSR set_return
    JMP ok_result

\ -------------------------------------------------------------------------
\ Socket_Close, Socket_Ioctl, Resolver_GetHostByName - plain success.
.cmd_ok
.cmd_resolve
    LDA #0
    JSR set_return
    JMP ok_result

\ -------------------------------------------------------------------------
\ Anything we do not implement reports an error.
.cmd_bad
    LDA #0
    LDY #2
    STA (blk), Y
    LDA #&FF
    LDY #3
    STA (blk), Y
    RTS

\ -------------------------------------------------------------------------
\ Socket_Recv - models the REAL module's behaviour: it satisfies the
\ requested count EXACTLY or not at all. Asking for more bytes than are
\ available yields &1E rather than a short read. This is the behaviour
\ that cost a day of debugging on hardware - see specification.md 5.5a.
.cmd_recv
    JSR find_chunk              \ src -> length byte of current chunk
    LDY #0
    LDA (src), Y
    BEQ recv_block              \ script exhausted: nothing available
    LDY #1
    SEC
    SBC (ws), Y                 \ available = length - offset
    BEQ recv_advance            \ this chunk is used up
    LDY #2
    STA (ws), Y                 \ save available

    LDY #12                     \ requested count (low byte is enough)
    LDA (blk), Y
    LDY #3
    STA (ws), Y
    BEQ recv_block              \ asked for zero: nothing to do

    LDY #2
    LDA (ws), Y                 \ available
    LDY #3
    CMP (ws), Y                 \ available - requested
    BCC recv_block              \ cannot satisfy in full -> would block

    LDY #1                      \ src := src + 1 + offset
    LDA (ws), Y
    SEC
    ADC src
    STA src
    BCC recv_nc
    INC src+1
.recv_nc

    LDY #8                      \ caller's buffer
    LDA (blk), Y : STA dst
    INY
    LDA (blk), Y : STA dst+1

    LDY #3
    LDA (ws), Y
    TAX                         \ X = bytes to copy
    LDY #0
.recv_copy
    LDA (src), Y
    STA (dst), Y
    INY
    DEX
    BNE recv_copy

    LDY #3                      \ offset += requested
    LDA (ws), Y
    LDY #1
    CLC
    ADC (ws), Y
    STA (ws), Y

    LDY #3
    LDA (ws), Y
    JSR set_return
    JMP ok_result

\ Current chunk consumed: step to the next one and report would-block,
\ so the caller polls again - exactly as the real module behaves.
.recv_advance
    LDY #0
    LDA (ws), Y
    CLC
    ADC #1
    STA (ws), Y
    LDA #0
    LDY #1
    STA (ws), Y

\ Nothing available: +4 = -1, +3 = &1E (would block), +2 zeroed.
.recv_block
    LDA #&FF
    LDY #4
    STA (blk), Y
    INY : STA (blk), Y
    INY : STA (blk), Y
    INY : STA (blk), Y
    LDA #0
    LDY #2
    STA (blk), Y
    LDA #&1E
    LDY #3
    STA (blk), Y
    RTS

\ ==========================================================================
\ Helpers
\ ==========================================================================

\ Per the Sprow API doc: +2 is zeroed on exit (this is the documented
\ way to detect the module's presence), +3 is the result code.
.ok_result
    LDA #0
    LDY #2
    STA (blk), Y
    LDY #3
    STA (blk), Y
    RTS

\ Store A as a 32-bit little-endian return value at +4.
.set_return
    PHA
    LDY #4
    PLA
    STA (blk), Y
    LDA #0
    INY : STA (blk), Y
    INY : STA (blk), Y
    INY : STA (blk), Y
    RTS

\ Walk the chunk table to the entry named by the workspace index.
.find_chunk
    LDA #LO(chunks) : STA src
    LDA #HI(chunks) : STA src+1
    LDY #0
    LDA (ws), Y
    TAX
    BEQ find_done
.find_skip
    LDY #0
    LDA (src), Y
    BEQ find_done               \ ran off the end: stay on the 0 terminator
    SEC                         \ src += length + 1
    ADC src
    STA src
    BCC find_nocarry
    INC src+1
.find_nocarry
    DEX
    BNE find_skip
.find_done
    RTS

\ ==========================================================================
\ Canned receive script: length byte, then that many bytes. 0 ends it.
\ ==========================================================================
.chunks
\ 1 - telnet negotiation. If PROCtelnet works these six bytes are
\     consumed and only "A" appears.
    EQUB c1_end - c1
.c1
    EQUB 255, 251, 1            \ IAC WILL ECHO
    EQUB 255, 251, 3            \ IAC WILL SGA
    EQUS "A", 13, 10
.c1_end

\ 2 - erase display. Should clear, not print "[2J".
    EQUB c2_end - c2
.c2
    EQUB 27
    EQUS "[2JB", 13, 10
.c2_end

\ 3 - absolute cursor position.
    EQUB c3_end - c3
.c3
    EQUB 27
    EQUS "[5;20HC", 13, 10
.c3_end

\ 4 - SGR colour, ignored on a 2-colour host screen but must not print.
    EQUB c4_end - c4
.c4
    EQUB 27
    EQUS "[1;32mD"
    EQUB 27
    EQUS "[0m", 13, 10
.c4_end

\ 5 - what a real shell actually sends and the parser used to print:
\     an OSC window title, which bash emits on EVERY prompt, and a
\     charset selection. Both must be swallowed whole - only "E"
\     should appear.
    EQUB c5_end - c5
.c5
    EQUB 27
    EQUS "]0;user@box: ~"
    EQUB 7                      \ BEL terminates the OSC
    EQUB 27
    EQUS "(B"                   \ ESC ( B - select ASCII, two bytes
    EQUS "E", 13, 10
.c5_end

\ 6 - the full-screen trio: scrolling region, alternate screen,
\     cursor save/restore. All must be swallowed; only "F" appears.
    EQUB c6_end - c6
.c6
    EQUB 27
    EQUS "[5;20r"                \ DECSTBM rows 5-20
    EQUB 27
    EQUS "7"                     \ save cursor
    EQUB 27
    EQUS "[?1049h"               \ alternate screen on
    EQUB 27
    EQUS "[?1049l"               \ and off again
    EQUB 27
    EQUS "8"                     \ restore cursor
    EQUB 27
    EQUS "[r"                    \ region back to full screen
    EQUS "F", 13, 10
.c6_end

\ 7 - a DCS string and an APC string, the shell-integration shapes
\     that are NOT OSC. Both must be swallowed; only "G" appears.
    EQUB c7_end - c7
.c7
    EQUB 27
    EQUS "P3008;start=deadbeef;user=user"
    EQUB 27
    EQUB 92                     \ ST is ESC backslash. EQUB, because
                                \ beebasm's EQUS does not treat \ as an
                                \ escape and "\\" emits TWO of them.
    EQUB 27
    EQUS "_type=shell;cwd=/home/user"
    EQUB 7                      \ BEL terminates this one
    EQUS "G", 13, 10
.c7_end

\ 8 - the real thing, captured from bash on the Linux box 2026-08-19:
\     an OSC terminated by ST, not by BEL. Chunk 5 covers OSC+BEL and
\     chunk 7 covers DCS+ST, but this exact combination was never
\     tested and it is the one a real shell actually sends.
    EQUB c8a_end - c8a
.c8a
    EQUB 27
    EQUS "]3008;start=41fa431e;user=user;hostname=deskbox;type=command"
    EQUB 27
    EQUB 92
    EQUS "H", 13, 10
.c8a_end

\ 9 - a plain prompt to finish on.
    EQUB c9_end - c9
.c9
    EQUS "login: "
.c9_end

    EQUB 0                      \ end of script

.rom_end
SAVE "build/SOCKSTUB", rom_start, &C000
