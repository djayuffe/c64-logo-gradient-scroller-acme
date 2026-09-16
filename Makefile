.PHONY: all clean

ACME ?= acme
OUTPUT := build/c64_logo_gradient_scroller_acme.prg
SOURCE := c64_logo_gradient_scroller_acme.s

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build
