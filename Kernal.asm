; ***             ***
; ***   KERNAL    ***
; ***             ***

; Main entry point
RESET:
  cld                           ; Clear decimal mode
  sei                           ; Disable interrupts

  ldx #$ff                      
  txs                           ; Reset the stack pointer

  lda #<IRQ                     ; Initialize the IRQ pointer
  sta IRQ_PTR
  lda #>IRQ
  sta IRQ_PTR + 1

  lda #<NMI                     ; Initialize the NMI pointer
  sta NMI_PTR
  lda #>NMI
  sta NMI_PTR + 1

  jsr INIT_BUFFER               ; Initialize the input buffer
  jsr INIT_IO                   ; Initialize the keypad and LCD
  jsr INIT_SC                   ; Initialize the serial output

  jsr LCD_CLEAR                 ; Clear the LCD (just in case)
  lda #<BANNER_ROW_1            ; Initialize the banner row 1 pointer
  sta STR_PTR
  lda #>BANNER_ROW_1
  sta STR_PTR + 1
  jsr LCD_PRINT

  lda #$40                      ; Cursor to row 2, column 0
  jsr LCD_PLOT
  lda #<BANNER_ROW_2            ; Initialize the banner row 2 pointer
  sta STR_PTR
  lda #>BANNER_ROW_2
  sta STR_PTR + 1
  jsr LCD_PRINT

  cli                           ; Enable interrupts

  jmp WOZ_MON                   ; Jump to Wozmon

; Initialize the IO (keypad and LCD)
INIT_IO:
  lda #$FF                      ; Set all pins on port B to output
  sta LCD_DDRB
  lda #(LCD_E | LCD_RW | LCD_RS); Set top 3 pins on port A to output
  sta LCD_DDRA
  lda #%00111000                ; Set 8-bit mode; 2-line display; 5x8 font
  jsr LCD_INSTRUCTION
  lda #%00001100                ; Display on; cursor off; blink off
  jsr LCD_INSTRUCTION
  lda #%00000110                ; Increment and shift cursor; don't shift display
  jsr LCD_INSTRUCTION
  lda #%10000010                ; Enable IRQ on CA1
  sta LCD_IER
  lda #%00001101                ; Set CA2 to LOW output, CA1 to positive edge
  sta LCD_PCR
  rts

; Initialize the serial output
; Modifies: Flags, A
INIT_SC:
  lda     #$1F                  ; 8-N-1, 19200 baud
  sta     SC_CTRL
  lda     #$09                  ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta     SC_CMD
  rts

; Initialize the INPUT_BUFFER
; Modifies: Flags, A
INIT_BUFFER:
  lda #$00
  sta READ_PTR                  ; Init read and write pointers
  sta WRITE_PTR
  rts

; Write a character from the A register to the INPUT_BUFFER
; Modifies: Flags, X
WRITE_BUFFER:
  ldx WRITE_PTR
  sta INPUT_BUFFER,x
  inc WRITE_PTR
  rts

; Read a character from the INPUT_BUFFER and store it in A register
; Modifies: Flags, X, A
READ_BUFFER:
  ldx READ_PTR
  lda INPUT_BUFFER,x
  inc READ_PTR
  rts

; Return in A register the number of unread bytes in the INPUT_BUFFER
; Modifies: Flags, A
BUFFER_SIZE:  
  lda WRITE_PTR
  sec
  sbc READ_PTR
  rts

; Get a character from the INPUT_BUFFER if available
; On return, carry flag indicates whether a character was available
; If character available the character will be in the A register
; Modifies: Flags, A
CHRIN:
  phx
  jsr BUFFER_SIZE               ; Check for character available
  beq @CHRIN_NO_CHAR            ; Branch if no character available
  jsr READ_BUFFER               ; Read the character from the buffer
  jsr CHROUT                    ; Echo
  pha                           
  jsr BUFFER_SIZE               
  cmp #$B0                      ; Check if buffer is mostly full
  bcc @CHRIN_NOT_FULL           ; Branch if buffer size < $B0
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
  bra @CHRIN_EXIT
@CHRIN_NOT_FULL:
  lda #$09                      ; No parity, no echo, RTSB low, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD
@CHRIN_EXIT:
  pla
  plx
  sec
  rts
@CHRIN_NO_CHAR:
  plx
  clc
  rts

; Output a character from the A register to the Serial Card
; Modifies: Flags
CHROUT:
  sta SC_DATA
  pha
@CHROUT_WAIT:
  lda SC_STATUS
  and #SC_STATUS_TDRE           ; Check if TX buffer not empty
  beq @CHROUT_WAIT              ; Loop if TX buffer not empty
  pla
  rts

; Send instruction in A register to LCD
; Modifies: Flags
LCD_INSTRUCTION:
  pha
  jsr LCD_WAIT
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
LCD_WAIT:
  pha
  lda #$00                      ; Port B is input
  sta LCD_DDRB
@LCD_WAIT_BUSY:
  lda #LCD_RW
  sta LCD_PORTA
  lda #(LCD_RW | LCD_E)
  sta LCD_PORTA
  lda LCD_PORTB
  and #$80                      ; Check the busy flag
  bne @LCD_WAIT_BUSY
@LCD_WAIT_EXIT:
  lda #LCD_RW
  sta LCD_PORTA
  lda #$FF                      ; Port B is output
  sta LCD_DDRB
  pla
  rts

; Clear the LCD display and return cursor to home
; Modifies: Flags
LCD_CLEAR:
  pha
  lda #$01                      ; Clear display
  jsr LCD_INSTRUCTION
  lda #$80                      ; Return cursor to home
  jsr LCD_INSTRUCTION
  pla
  rts

; Outputs character from the A register to LCD at cursor position
; Modifies: Flags
LCD_CHROUT:
  pha
  jsr LCD_WAIT
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
LCD_PRINT:
  pha                           ; Save A, Y to stack
  tya
  pha
  ldy #$00
@LCD_PRINT_LOOP:
  lda (STR_PTR),y               ; Load next character at location pointed to by STR_PTR offset by Y
  beq @LCD_PRINT_EXIT
  jsr LCD_CHROUT
  iny
  bne @LCD_PRINT_LOOP
@LCD_PRINT_EXIT:
  pla                           ; Restore A, Y
  tay
  pla
  rts

; Sets the LCD cursor position using the value in A register
; Input: Accumulator = desired DDRAM address (e.g., $00-$0F for row 1, $40-$4F for row 2)
; Modifies: Flags
LCD_PLOT:
  ora #%10000000                ; Set bit 7 to make it a "Set DDRAM Address" command ($80)
  jsr LCD_INSTRUCTION           ; Send command
  rts

; Convert value in A register to two byte HEX value as ASCII and write to INPUT_BUFFER
; Modifies: Flags, Y
HEX_TO_ASCII:
  pha                           ; Save original A value
  lsr                           ; Shift high nibble into low nibble
  lsr
  lsr
  lsr
  tay
  lda HEX_ASCII,y               ; Convert to ASCII
  jsr WRITE_BUFFER              ; Write to INPUT_BUFFER
  pla                           ; Restore original A value
  pha
  and #$0F                      ; Mask low nibble
  tay
  lda HEX_ASCII,y               ; Convert to ASCII
  jsr WRITE_BUFFER              ; Write to INPUT_BUFFER
  pla
  rts

; NMI Handler
NMI:
  rti

; IRQ Handler
IRQ:
  pha
  phy
  phx
@IRQ_SC:
  lda SC_STATUS
  and #SC_STATUS_IRQ            ; Check if serial data caused the interrupt
  beq @IRQ_LCD                  ; If not, continue
  lda SC_DATA                   ; Read the data from serial register
  jsr WRITE_BUFFER              ; Store to the input buffer
  jsr BUFFER_SIZE
  cmp #$F0                      ; Is the buffer almost full?
  bcc @IRQ_LCD                  ; If not, continue
  lda #$01                      ; No parity, no echo, RTSB high, TX interrupts disabled, RX interrupts enabled
  sta SC_CMD                    ; Otherwise, signal not ready for receiving (RTSB high)
@IRQ_LCD:
  lda LCD_IFR
  and #%00000010                ; Check if CA1 caused the interrupt
  beq @IRQ_EXIT                 ; If not, exit
  lda LCD_PORTA                 ; Read the data from VIA PORTA
  and #%00011111                ; Mask off the lower five bits to read keypad data
  sta KEYPAD_IN                 ; Store to the zero page for now
@IRQ_EXIT:
  plx
  ply
  pla
  rti

; NMI Vector
NMI_VEC:
  jmp (NMI_PTR)                 ; Indirect jump through NMI pointer to the NMI handler

; Reset Vector
RESET_VEC:
  jmp RESET                     ; Initialize the system

; IRQ Vector
IRQ_VEC:
  jmp (IRQ_PTR)                 ; Indirect jump through IRQ pointer to the IRQ handler

; HEX to ASCII conversion lookup table
HEX_ASCII: .asciiz "0123456789ABCDEF"

; Banner message
BANNER_ROW_1: .asciiz "-- THE 'KIM' ---"
BANNER_ROW_2: .asciiz "--   v 1.0   ---"