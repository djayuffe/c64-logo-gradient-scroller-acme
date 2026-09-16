# DeepSeek v9 logo/gradient scroller — ACME

PAL C64 demo source with embedded dual charsets, centered logo text, gradient
colors, raster bars, SID arpeggio, and a bottom scroller.

## Build and run

```sh
acme --strict-segments -f cbm -o v9_logo_grad.prg \
  deepseek_asm_20251009_v9_logo_grad_scroller_embedded_fonts_vicfix_acme.s
x64sc -autostart v9_logo_grad.prg
```

The source no longer depends on an absent external charset or overlaps code
with the embedded font. Charset A/B are emitted at `$2000`/`$2800`, and the
centered text routine preserves both row and color state.
