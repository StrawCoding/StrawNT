# StrawNT NTW4 PE fixtures (MinGW)
# Do not inherit host CC= (often plain gcc) — always cross-compile.
MINGW_CC ?= x86_64-w64-mingw32-gcc
BUILD := build
CFLAGS ?= -O2 -s

.PHONY: all clean

all: $(BUILD)/strawnt_ac_stub.exe $(BUILD)/strawnt_game_stub.exe

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/strawnt_ac_stub.exe: strawnt_ac_stub.c | $(BUILD)
	$(MINGW_CC) $(CFLAGS) -o $@ $< -lws2_32

$(BUILD)/strawnt_game_stub.exe: strawnt_game_stub.c | $(BUILD)
	$(MINGW_CC) $(CFLAGS) -o $@ $< -lws2_32

clean:
	rm -rf $(BUILD)
