; ***             ***
; ***   KERNAL    ***
; ***             ***

; Main entry point
Reset:
  cld                           ; Clear decimal mode
  sei                           ; Disable interrupts

  ldx #$ff                      
  txs                           ; Reset the stack pointer

  lda #<Irq                     ; Initialize the IRQ pointer
  sta IRQ_PTR
  lda #>Irq
  sta IRQ_PTR + 1

  lda #<Nmi                     ; Initialize the NMI pointer
  sta NMI_PTR
  lda #>Nmi
  sta NMI_PTR + 1

  jsr InitBuffer                ; Initialize the input buffer
  jsr InitSc                    ; Initialize the serial output
  jsr InitIo                    ; Initialize the keypad and LCD

  jsr LcdClear                  ; Clear the LCD (just in case)
  lda #<BannerRow1              ; Initialize the banner row 1 pointer
  sta STR_PTR
  lda #>BannerRow1
  sta STR_PTR + 1
  jsr LcdPrint

  lda #$40                      ; Cursor to row 2, column 0
  jsr LcdPlot
  lda #<BannerRow2              ; Initialize the banner row 2 pointer
  sta STR_PTR
  lda #>BannerRow2
  sta STR_PTR + 1
  jsr LcdPrint

  cli                           ; Enable interrupts

  jmp WozMon                    ; Jump to Wozmon

; Initialize the IO (keypad and LCD)
InitIo:
  lda #$FF                      ; Set all pins on port B to output
  sta LCD_DDRB
  lda #(LCD_E | LCD_RW | LCD_RS); Set top 3 pins on port A to output
  sta LCD_DDRA
  lda #%00111000                ; Set 8-bit mode; 2-line display; 5x8 font
  jsr LcdInstruction
  lda #%00001100                ; Display on; cursor off; blink off
  jsr LcdInstruction
  lda #%00000110                ; Increment and shift cursor; don't shift display
  jsr LcdInstruction
  lda #%10000010                ; Enable IRQ on CA1
  sta LCD_IER
  lda #%00001101                ; Set CA2 to LOW output, CA1 to positive edge
  sta LCD_PCR
  rts

; Initialize the serial output
; Modifies: Flags, A
InitSc:
  lda     #$1F                  ; 8-N-1, 19200 baud
  sta     SC_CTRL
  lda     #$09                  ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta     SC_CMD
  rts

; Initialize the INPUT_BUFFER
; Modifies: Flags, A
InitBuffer:
  lda #$00
  sta READ_PTR                  ; Init read and write pointers
  sta WRITE_PTR
  rts

; Write a character from the A register to the INPUT_BUFFER
; Modifies: Flags, X
WriteBuffer:
  ldx WRITE_PTR
  sta INPUT_BUFFER,x
  inc WRITE_PTR
  rts

; Read a character from the INPUT_BUFFER and store it in A register
; Modifies: Flags, X, A
ReadBuffer:
  ldx READ_PTR
  lda INPUT_BUFFER,x
  inc READ_PTR
  rts

; Return in A register the number of unread bytes in the INPUT_BUFFER
; Modifies: Flags, A
BufferSize:  
  lda WRITE_PTR
  sec
  sbc READ_PTR
  rts

; Get a character from the INPUT_BUFFER if available
; On return, carry flag indicates whether a character was available
; If character available the character will be in the A register
; Modifies: Flags, A
Chrin:
  phx
  jsr BufferSize                ; Check for character available
  beq @ChrinNoChar              ; Branch if no character available
  jsr ReadBuffer                ; Read the character from the buffer
  jsr Chrout                    ; Echo
  pha                           
  jsr BufferSize               
  cmp #$B0                      ; Check if buffer is mostly full
  bcc @ChrinNotFull             ; Branch if buffer size < $B0
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
  bra @ChrinExit
@ChrinNotFull:
  lda #$09                      ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
@ChrinExit:
  pla
  plx
  sec
  rts
@ChrinNoChar:
  plx
  clc
  rts

; Output a character from the A register to the Serial Card
; Modifies: Flags
Chrout:
  sta SC_DATA
  pha
@ChroutWait:
  lda SC_STATUS
  and #SC_STATUS_TDRE           ; Check if TX buffer not empty
  beq @ChroutWait               ; Loop if TX buffer not empty
  pla
  rts

; Send instruction in A register to LCD
; Modifies: Flags
LcdInstruction:
  pha
  jsr LcdWait
  sta LCD_PORTB
  lda #0                        ; Clear RS/RW/E bits
  sta LCD_PORTA
  lda #LCD_E                    ; Set E bit to send instruction
  sta LCD_PORTA
  lda #0                        ; Clear RS/RW/E bits
  sta LCD_PORTA
  pla
  rts

; Wait for LCD busy flag to clear
; Modifies: Flags
LcdWait:
  pha
  lda #$00                      ; Port B is input
  sta LCD_DDRB
@LcdWaitBusy:
  lda #LCD_RW
  sta LCD_PORTA
  lda #(LCD_RW | LCD_E)
  sta LCD_PORTA
  lda LCD_PORTB
  and #$80                      ; Check the busy flag
  bne @LcdWaitBusy
@LcdWaitExit:
  lda #LCD_RW
  sta LCD_PORTA
  lda #$FF                      ; Port B is output
  sta LCD_DDRB
  pla
  rts

; Clear the LCD display and return cursor to home
; Modifies: Flags
LcdClear:
  pha
  lda #$01                      ; Clear display
  jsr LcdInstruction
  lda #$80                      ; Return cursor to home
  jsr LcdInstruction
  pla
  rts

; Outputs character from the A register to LCD at cursor position
; Modifies: Flags
LcdChrout:
  pha
  jsr LcdWait
  sta LCD_PORTB
  lda #LCD_RS                   ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(LCD_RS | LCD_E)         ; Set E bit to send instruction
  sta LCD_PORTA
  lda #LCD_RS                   ; Clear E bits
  sta LCD_PORTA
  pla
  rts

; Outputs string pointed to with STR_PTR to LCD at cursor position
; Modifies: Flags
LcdPrint:
  pha                           ; Save A, Y to stack
  tya
  pha
  ldy #$00
@LcdPrintLoop:
  lda (STR_PTR),y               ; Load next character at location pointed to by STR_PTR offset by Y
  beq @LcdPrintExit
  jsr LcdChrout
  iny
  bne @LcdPrintLoop
@LcdPrintExit:
  pla                           ; Restore A, Y
  tay
  pla
  rts

; Sets the LCD cursor position using the value in A register
; Input: Accumulator = desired DDRAM address (e.g., $00-$0F for row 1, $40-$4F for row 2)
; Modifies: Flags
LcdPlot:
  ora #%10000000                ; Set bit 7 to make it a "Set DDRAM Address" command ($80)
  jsr LcdInstruction            ; Send command
  rts

; Convert value in A register to two byte HEX value as ASCII and write to INPUT_BUFFER
; Modifies: Flags, Y
HexToAscii:
  pha                           ; Save original A value
  lsr                           ; Shift high nibble into low nibble
  lsr
  lsr
  lsr
  tay
  lda HexAscii,y                ; Convert to ASCII
  jsr WriteBuffer               ; Write to INPUT_BUFFER
  pla                           ; Restore original A value
  pha
  and #$0F                      ; Mask low nibble
  tay
  lda HexAscii,y                ; Convert to ASCII
  jsr WriteBuffer               ; Write to INPUT_BUFFER
  pla
  rts

; NMI Handler
Nmi:
  rti

; IRQ Handler
Irq:
  pha
  phy
  phx
@IrqSc:
  lda SC_STATUS
  and #SC_STATUS_IRQ            ; Check if serial data caused the interrupt
  beq @IrqLcd                   ; If not, continue
  lda SC_DATA                   ; Read the data from serial register
  jsr WriteBuffer               ; Store to the input buffer
  jsr BufferSize
  cmp #$F0                      ; Is the buffer almost full?
  bcc @IrqLcd                   ; If not, continue
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD                    ; Otherwise, signal not ready for receiving (RTSB high)
@IrqLcd:
  lda LCD_IFR
  and #%00000010                ; Check if CA1 caused the interrupt
  beq @IrqExit                  ; If not, exit
  lda LCD_PORTA                 ; Read the data from VIA PORTA
  and #%00011111                ; Mask off the lower five bits to read keypad data
  sta KEYPAD_IN                 ; Store to the zero page for now
@IrqExit:
  plx
  ply
  pla
  rti

; NMI Vector
NmiVec:
  jmp (NMI_PTR)                 ; Indirect jump through NMI pointer to the NMI handler

; Reset Vector
ResetVec:
  jmp Reset                     ; Initialize the system

; IRQ Vector
IrqVec:
  jmp (IRQ_PTR)                 ; Indirect jump through IRQ pointer to the IRQ handler

; HEX to ASCII conversion lookup table
HexAscii: .asciiz "0123456789ABCDEF"

; Banner message
BannerRow1: .asciiz "-- THE 'KIM' ---"
BannerRow2: .asciiz "--   v 1.0   ---"