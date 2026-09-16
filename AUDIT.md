# Audit record

The supplied ACME source referenced a missing `custom_charset_1bpp.bin` and
overlapped that external segment with the embedded charset. The helper routine
was consequently emitted inside the font data, and the centered text routine
lost its row argument while measuring the string.

Repairs:

- removed the redundant external charset input;
- emitted charset A at `$2000` and charset B at `$2800`;
- moved `VIC_BankFix` before the font segments;
- disabled CIA IRQ sources during startup;
- preserved row and color state in `CenterPrintRow`.

Validation: ACME `--strict-segments` succeeds with no external input files.
Corrected build SHA-256: `cb120e887fe74f7a9d2e4383ec1b3f38b34d2ef8bc5cfb2972583ae8a6346318`.
