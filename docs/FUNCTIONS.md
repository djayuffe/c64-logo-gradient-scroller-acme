# Function reference

This is the native ACME implementation of the logo/gradient scroller.

| Function | Responsibility |
|---|---|
| Start / IRQ_Init | Initializes VIC/CIA state and installs raster timing. |
| CenterPrintRow | Centers text while preserving row and color state. |
| ColorizeLogo / ColorizeRowGrad | Applies the logo and row gradients. |
| InitScroller / Scroller_Tick | Initializes and advances the bottom scroller. |
| SID_Init / SID_Tick | Initializes the SID and advances the arpeggio. |
| VIC_BankFix | Selects the VIC bank used by the demo. |
| Charset_A / Charset_B | Embedded character sets emitted at $2000/$2800. |

AUDIT.md documents the layout and strict-segment validation.
