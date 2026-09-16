# C64 v9 ACME

![C64 effect preview](docs/preview.png)

Visual preview asset for this effect; run the VICE command below for an emulator capture.

PAL C64 demo with dual charsets, centered logo text, gradient colors, raster
bars, SID arpeggio, and a bottom scroller.

## Build

Requires ACME 0.97 or newer:

```sh
make
```

Output: `build/c64_logo_gradient_scroller_acme.prg`. Run with:

```sh
x64sc -autostart build/c64_logo_gradient_scroller_acme.prg
```

## Repository layout

- `c64_logo_gradient_scroller_acme.s` — corrected ACME source.
- `Makefile`, `AUDIT.md`, and `SHA256SUMS.txt` — build, audit, and integrity data.

## Audit summary

Missing external charset input and font/code overlap were removed. Charsets are
placed at `$2000`/`$2800`, CIA IRQ sources are disabled during startup, and the
centered text routine preserves row and color state.
## Documentation and license

Function-level documentation is in docs/FUNCTIONS.md. The project is released
under GPL-3.0; see LICENSE.
