#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#define KeypadScan 0x0003D0

struct ti_rom_t {
    uint8_t boot_code[0x20000];
    uint8_t os_code[0x0A0000];
    uint8_t cert[0x10000];
};

static const char bin[] = {
    #embed "UPDATE.bin"
};

static long file_size(FILE *file)
{
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    return size;
}

static bool load_rom(const char *path, struct ti_rom_t *rom)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "specified ROM file does not exist\n");
        return false;
    }

    int ret = false;

    if (file_size(f) != 0x400000) {
        fprintf(stderr, "incorrect ROM size\n");
        goto cleanup;
    }

    if (fread(rom->boot_code, sizeof(rom->boot_code), 1, f) != 1) {
        fprintf(stderr, "failed to read boot code\n");
        goto cleanup;
    }

    if (fread(rom->os_code, sizeof(rom->os_code), 1, f) != 1) {
        fprintf(stderr, "failed to load OS code\n");
        goto cleanup;
    }

    if (fseek(f, 0x3B0000, SEEK_SET)) {
        fprintf(stderr, "failed to seek cert\n");
        goto cleanup;
    }

    if (fread(rom->cert, sizeof(rom->cert), 1, f) != 1) {
        fprintf(stderr, "failed to read cert\n");
        goto cleanup;
    }

    ret = true;
cleanup:
    fclose(f);
    return ret;
}

static bool write_rom(const char *path, struct ti_rom_t *rom)
{
    FILE *f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "failed to create output\n");
        return false;
    }

    int ret = false;

    if (fwrite(rom->boot_code, sizeof(rom->boot_code), 1, f) != 1) {
        fprintf(stderr, "failed to write boot code\n");
        goto cleanup;
    }

    if (fwrite(rom->os_code, sizeof(rom->os_code), 1, f) != 1) {
        fprintf(stderr, "failed to write os code\n");
        goto cleanup;
    }

    // fill remainder with FF
    static uint8_t block[0x10000];
    memset(block, 0xFF, sizeof(block));
    for (int i = 0x0C; i < 0x40; i++) {
        if (fwrite(block, sizeof(block), 1, f) != 1) {
            fprintf(stderr, "failed to write block\n");
            goto cleanup;
        }
    }
    
    if (fseek(f, 0x3B0000, SEEK_SET)) {
        fprintf(stderr, "failed to seek cert\n");
        goto cleanup;
    }

    if (fwrite(rom->cert, sizeof(rom->cert), 1, f) != 1) {
        fprintf(stderr, "failed to write cert\n");
        goto cleanup;
    }

    ret = true;
cleanup:
    fclose(f);
    return ret;
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <rom_file>\n", argv[0]);
        return EXIT_FAILURE;
    }

    static struct ti_rom_t rom;
    char *input_rom_path = argv[1];
    if (!load_rom(input_rom_path, &rom)) return EXIT_FAILURE;

    uint8_t *jp_instr = &rom.boot_code[KeypadScan];
    if (jp_instr[0] != 0xC3) {
        fprintf(stderr, "cannot find ti.KeypadScan in jump table\n");
        return EXIT_FAILURE;
    }

    uint8_t call_instr[] = {0xCD, jp_instr[1], jp_instr[2], jp_instr[3]};
    uint8_t *match = memmem(rom.boot_code, sizeof(rom.boot_code), call_instr, 4);
    if (!match) {
        fprintf(stderr, "could not find sequence\n");
        return EXIT_FAILURE;
    }

    uint8_t *b = (uint8_t*)bin;
    size_t b_size = sizeof(bin);

    // skip header
    b += 3;
    b_size -= 3;

    // skip version
    b += 3;
    b_size -= 3;

    // replace call address
    match[1] = 0xFC;
    match[2] = 0xFF;
    match[3] = 0x01;

    // copy patch code
    memcpy(rom.boot_code + (sizeof(rom.boot_code) - b_size), b, b_size);

    char *ext = strrchr(input_rom_path, '.');
    char new_name[64];
    snprintf(new_name, sizeof(new_name),
             "%.*s_PATCHED%s",
             (int)(ext - input_rom_path),
             input_rom_path,
             ext);

    if (!write_rom(new_name, &rom)) {
        fprintf(stderr, "failed to write output rom\n");
        return EXIT_FAILURE;
    }

    printf("done! wrote %s\n", new_name);
    return EXIT_SUCCESS;
}