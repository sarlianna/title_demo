  .inesprg 1
  .ineschr 1
  .inesmap 0
  .inesmir 0      ;horizontal mirroring for vertical scrolling

;;;;;;;;;;;;;;;;;;;;

  .rsset $0000

scroll      .rs 1
nametable   .rs 1
staticHigh  .rs 1
staticLow   .rs 1

;;;;;;;;;;;;;;;;;;;;

  .bank 0
  .org $C000
Reset:
  SEI
  CLD
  LDX #$40
  STX $4017       ; disable APU frame IRQ
  LDX #$FF
  TXS             ; set up stack
  INX             ; x = 0
  STX $2000       ; disable NMI by writing to PPUCTRL (clear 7th bit disables NMI)
  STX $2001       ;disable rendering 
  STX $4010       ;disable DMC IRQs

vblankwait1:      ;we wait for vblank.  This is to give the PPU time to start up.
  BIT $2002
  BPL vblankwait1

clrmem:           ;use the time to get RAM into a known state.
  LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0300, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE        ;$0200 will be used for sprites, which must be initialized to $FE or garbage will get rendered.
  STA $0200, x
  INX
  BNE clrmem

vblankwait2:      ;second vblank wait, PPU is ready afterward
  BIT $2002
  BPL vblankwait2

LoadPalettes:
  LDA $2002       ;reset high/low latch
  LDA #$3F        ;point PPU to $3FOO, the palette that determines universal background color
  STA $2006
  LDA #$00
  STA $2006
  LDX #$00
.loop:
  LDA palette, x
  STA $2007       ;hand off the data to the PPU.  It will handle storage and incrementing its internal pointer.
  INX
  CPX #$20
  BNE loop

LoadSprites:
  LDX #$00
.loop:
  LDA sprites, x
  STA $0200, x     ;We copy sprites to CPU RAM, at $0200.  These will be copied to OAM each frame using OAM_DMA($4014)
  INX
  CPX #$10
  BNE loop

;next is the background.  Normally you would set it by copying 4 pieces after setting the PPU address once, 
;but we don't actually need all of the first nametable filled, because it won't be seen until after we start scrolling.
  LDA $2002        ;reset high/low byte latch
  LDA #$20         ;point PPU to $2000, the start of the first nametable.
  STA $2006
  LDA #$00
  STA $2006
  LDX #$00
LoadBackground1:
  LDA background1, x
  STA $2007
  INX
  CPX #$00
  BNE LoadBackground1
  
LoadBackground2:   ;we know X contains #$00 at this point
  LDA background2, x
  STA $2007
  INX
  CPX #$00
  BNE LoadBackground2

  LDA $2002       ;reset high/low latch
  LDA #$2A        ;point PPU to $2A00, which lies halfway through nametable 2
  STA $2006
  LDA #$00
  STA $2006
LoadBackground3:
  LDA background3, x
  STA $2007
  INX
  CPX #$00
  BNE LoadBackground3

LoadBackground4:
  LDA background4, x
  STA $2007
  INX
  CPX #$00
  BNE LoadBackground4

LoadAttributes1st:    ;PPU address is currently at nametable 2's attribute data
  LDA attribute2, x   ;so we copy its data before nametable 1's
  STA $2007
  INX
  CPX #$40
  BNE LoadAttributes1st

  LDA $2002           ;reset latch
  LDA #$23            ;point PPU to $23J0, the start of nametable 0's attribute data
  STA $2006
  LDA #$C0
  STA $2006
  LDX #$00
LoadAttributes2nd:
  LDA attribute1, x
  STA $2007
  INX
  CPX #$40
  BNE LoadAttributes2nd


  LDA $2002         ;reset scroll and PPU address registers
  LDA #$00
  STA $2005
  STA $2005
  STA $2006
  STA $2006

  LDA #%10010000   ;enable NMI, assign pattern table 0 to sprites and pattern table 1 to background
  STA $2000        ;PPUCTRL

  LDA #%00011110   ;enable sprites and background, disable clipping on left side
  STA $2001        ;PPUMASK

Forever:
  JMP Forever     ;From now on we only need to do logic during NMI.
                  ;In a full game, putting logic here is fine. (logic unrelated to rendering)

NMI:
  LDA #$00        ;low byte of RAM address containing sprite data
  STA $2003       ;OAM address
  LDA #$02        ;high byte of RAM containing sprite data
  STA $4014       ;OAM_DMA.  This will begin copying sprite data for us.

;Graphic update code:
;check current scroll, and render any background rows just past the seam
;   this includes text that is about to be shown AND static image data (which must be written far in advance,
;   as the image is too large to be done in one frame)
;if current scroll will soon overlap the static image, change image locations and write
;    new palette data for it (?)
;update variables (scroll, sprite locations)

  LDA #$00
  STA $2006
  STA $2006       ;Necessary??

  LDA #$00        ;Set no horizontal scroll and current vertical scroll.
  STA $2005
  LDA scroll
  STA $2005

  LDA #%10010000  ;Ensure we're pointed at the correct nametable
  ORA nametable
  STA $2000

  LDA #%00011110   ;Reset sprite settings
  STA $2001
  

VblankEndWait:    ;at the end of vblank, sprite 0 flag is cleared.  We wait for this to ensure
  LDA $2002       ;the set flag is on this frame, and not left over from last frame.
  AND #%01000000  ;bit 6 of $2002 is the sprite 0 flag
  BNE VblankEndWait

Sprite0Wait:
  LDA $2002
  AND #%01000000
  BEQ Sprite0Wait

  LDX #$10        ;amount of time needed to wait after sprite 0 hit may change after graphics are set
WaitScanline:
  DEX
  BNE WaitScanline

  LDA staticHigh      ;Point PPU to where our static graphic section currently resides
  STA $2006
  LDA staticLow
  STA $2006

  RTI


;;;;;;;;;;;;;

  .bank 1
  .org $E000
palette:
  .db $,$,$,$,  $,$,$,$,  $,$,$,$,  $,$,$,$   ;background palette
  .db  ;sprite palette

sprites:
  .db $00, $00, $00, $00  ;sprite 0
  .db $00, $00, $00, $00

background1:
  .db $, $, $, $, $, $, $, $, $, $, $, $, $, $, $, $, $
  .db

background2:
  .db
  .db

background3:
  .db
  .db

background4:
  .db
  .db

background5:
  .db
  .db

background6:
  .db
  .db

background7:
  .db
  .db

background8:
  .db
  .db

attribute1:
  .db
  .db

attribute2:
  .db
  .db

  .org $FFFA
  .dw NMI   ;address to jump to when an NMI happens
  .dw RESET ;address to jump to on reset  or power on
  .dw 0     ;external interrupt IRQ

;;;;;;;;;;;;;;;

  .bank 2
  .org $0000
  .incbin ""   ;graphics file to be included
