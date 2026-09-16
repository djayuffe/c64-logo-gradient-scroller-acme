.PHONY: all clean

ACME ?= acme
OUTPUT := build/v9_logo_grad.prg
SOURCE := deepseek_asm_20251009_v9_logo_grad_scroller_embedded_fonts_vicfix_acme.s

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build
