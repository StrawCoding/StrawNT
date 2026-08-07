# StrawNT NTW5 App Manager PE fixture (MinGW)
# Do not inherit host CC= — always cross-compile.
MINGW_CC ?= x86_64-w64-mingw32-gcc
BUILD := build
CFLAGS ?= -O2 -s

.PHONY: all clean

all: $(BUILD)/strawnt_app_stub.exe

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/strawnt_app_stub.exe: strawnt_app_stub.c | $(BUILD)
	$(MINGW_CC) $(CFLAGS) -o $@ $<

clean:
	rm -rf $(BUILD)
