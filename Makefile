CC := clang
FASMG := fasmg

CFLAGS := -Wall -Wextra
ifdef WITH_SYMBOLS
FFLAGS := -i 'include "symbol_table.inc"'
endif

SRC := installer.c
TARGET := ce-rom-patcher
ASM_SRC := src/patch.asm
ASM_OUT := UPDATE.8xv UPDATE.bin UPDATE.lab
APPVAR := UPDATE.8xv

all: $(TARGET)

$(APPVAR): $(ASM_SRC)
	$(FASMG) $(FFLAGS) $(ASM_SRC) $(APPVAR)

$(TARGET): $(SRC) $(APPVAR)
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET)

clean:
	rm -f $(TARGET) $(ASM_OUT)