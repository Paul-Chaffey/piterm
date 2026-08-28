\ ==========================================================================
\ NEWTERM - a fast VT102 terminal ROM for the BBC Master 128
\ ==========================================================================
\ Build:  make          (produces build/newterm.rom, a 16K sideways ROM)
\ Use:    *TERM         to enter, f0 to exit
\
\ Design notes: see docs/architecture.md
\ ==========================================================================

CPU 1                       \ 65C12 - Master 128. Set to 0 for 6502/Model B.

\ ---------------------------------------------------------------- MOS API
OSWRCH      = &FFEE
OSASCI      = &FFE3
OSNEWL      = &FFE7
OSBYTE      = &FFF4
OSWORD      = &FFF1
OSCLI       = &FFF7

\ ------------------------------------------------------------- Hardware
ACIA_STATUS = &FE08         \ read:  6850 status
ACIA_CTRL   = &FE08         \ write: 6850 control
ACIA_DATA   = &FE09         \ read:  RX data,  write: TX data
SERIAL_ULA  = &FE10         \ write only; MOS keeps a copy at &0282
ACCCON      = &FE34         \ Master only: shadow/HAZEL control
ROMSEL      = &FE30

\ 6850 status register bits
ACIA_RDRF   = &01           \ receive data register full
ACIA_TDRE   = &02           \ transmit data register empty
ACIA_DCD    = &04
ACIA_CTS    = &08
ACIA_OVRN   = &20           \ receiver overrun
ACIA_IRQ    = &80

\ ------------------------------------------------------------- MOS vectors
IRQ1V       = &0204
ULA_COPY    = &0282         \ MOS's shadow copy of the serial ULA register

\ ------------------------------------------------------------ Zero page
\ &70-&8F is the user/BASIC zero page. NEWTERM is a foreground application:
\ it takes the machine over, so it is free to use this. Anything the current
\ language had here is lost - same bargain Acorn's own TERM makes.
zp_cmdptr   = &70           \ 2 - pointer into the command line (service &04)
zp_tmp      = &72           \ 2 - general scratch
zp_oldirq   = &74           \ 2 - previous IRQ1V, so we can chain
zp_rxhead   = &76           \ 1 - RX ring write index (IRQ side)
zp_rxtail   = &77           \ 1 - RX ring read index  (main side)
zp_flags    = &78           \ 1 - see FLAG_* below
zp_baud     = &79           \ 1 - serial ULA value in use
zp_char     = &7A           \ 1 - character being processed

FLAG_XOFF   = &01           \ we have sent XOFF to the host
FLAG_EXIT   = &02           \ main loop should terminate

\ ------------------------------------------------------------- Workspace
\ Claimed above OSHWM at run time. The RX ring is page-aligned so the IRQ
\ handler can index it with a single 8-bit register and no masking.
RXBUF       = &0E00         \ 256 bytes. Placeholder - relocated at entry.

XON         = &11
XOFF        = &13

\ ==========================================================================
ORG   &8000
GUARD &C000

.rom_start
\ -------------------------------------------------------------- ROM header
    BRK                     \ no language entry
    BRK
    BRK
    JMP service_entry
    EQUB &82                \ ROM type: service entry, 6502 code
    EQUB copyright - rom_start
    EQUB 1                  \ binary version
.rom_title
    EQUS "NEWTERM", 0
.rom_version
    EQUS "0.01", 0
.copyright
    EQUB 0
    EQUS "(C)2026", 0

\ ==========================================================================
\ Service call handler
\ ==========================================================================
.service_entry
    CMP #&04                \ unrecognised * command
    BEQ srv_command
    CMP #&09                \ *HELP
    BEQ srv_help
.srv_exit
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
    JSR OSNEWL
    PLA : TAY : PLA : TAX : PLA
    RTS

.help_text
    EQUS "NEWTERM 0.01", 13
    EQUS "  TERM", 13, 0

\ -------------------------------------------------------------------------
\ A=4, X=ROM slot, Y=offset of the command text within &F2/&F3
.srv_command
    PHA : TXA : PHA : TYA : PHA

    LDA &F2 : STA zp_cmdptr
    LDA &F3 : STA zp_cmdptr+1

    LDX #0
.cmp_loop
    LDA (zp_cmdptr), Y
    JSR to_upper
    CMP cmd_term, X
    BNE cmd_no_match
    INY : INX
    CPX #4                  \ "TERM"
    BNE cmp_loop

    \ Matched. Terminator must be a separator, not more letters.
    LDA (zp_cmdptr), Y
    CMP #&21
    BCS cmd_no_match

    JSR term_main

    PLA : TAY : PLA : TAX : PLA
    LDA #0                  \ claim the call
    RTS

.cmd_no_match
    PLA : TAY : PLA : TAX : PLA
    RTS

.cmd_term
    EQUS "TERM"

\ -------------------------------------------------------------------------
.to_upper
    CMP #'a'
    BCC to_upper_done
    CMP #'z'+1
    BCS to_upper_done
    SBC #&1F                \ carry is clear here, so this subtracts &20
.to_upper_done
    RTS

INCLUDE "src/serial.asm"
INCLUDE "src/main.asm"

.rom_end
SAVE "build/newterm.rom", rom_start, &C000
