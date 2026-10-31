#include "CSensors.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

// AppleSMC's 80-byte user-client packet. Commands 5, 8 and 9 only read.
typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} Packet;
_Static_assert(sizeof(Packet) == 80, "Unexpected AppleSMC ABI");
_Static_assert(offsetof(Packet, bytes) == 48, "Unexpected AppleSMC byte offset");

static uint32_t fourcc(const char *s) {
    return (uint32_t)(uint8_t)s[0] << 24 | (uint32_t)(uint8_t)s[1] << 16 |
           (uint32_t)(uint8_t)s[2] << 8 | (uint8_t)s[3];
}
static int32_t call(uint32_t connection, const Packet *input, Packet *output) {
    size_t size = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    if (result != KERN_SUCCESS) return result;
    if (size != sizeof(*output)) return -1;
    return output->result == 0 ? 0 : -(1000 + output->result);
}
int32_t tc_open(uint32_t *connection) {
    *connection = 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}
void tc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }
int32_t tc_read(uint32_t connection, const char *key, TCValue *value) {
    memset(value, 0, sizeof(*value));
    if (!connection || !key || strlen(key) != 4) return -2;
    Packet input = {0}, output = {0};
    input.key = fourcc(key);
    input.command = 9;
    int32_t result = call(connection, &input, &output);
    if (result) return result;
    if (!output.info.size || output.info.size > 32) return -3;
    value->type = output.info.type;
    value->size = output.info.size;
    input.info.size = value->size;
    input.command = 5;
    memset(&output, 0, sizeof(output));
    result = call(connection, &input, &output);
    if (!result) memcpy(value->bytes, output.bytes, value->size);
    return result;
}
int32_t tc_key_at(uint32_t connection, uint32_t index, char key[5]) {
    Packet input = {0}, output = {0};
    input.command = 8;
    input.index = index;
    int32_t result = call(connection, &input, &output);
    if (result) return result;
    for (int i = 0; i < 4; i++) key[i] = (char)(output.key >> (24 - 8 * i));
    key[4] = 0;
    return 0;
}
static int hex_digit(uint8_t x) {
    if (x >= '0' && x <= '9') return x - '0';
    if (x >= 'a' && x <= 'f') return x - 'a' + 10;
    return -1;
}
bool tc_decode(const TCValue *value, double *number) {
    if (!value || !number || !value->size || value->size > 32) return false;
    const uint8_t *b = value->bytes;
    uint32_t type = value->type;
    if (type == fourcc("flt ") && value->size == 4) {
        uint32_t bits = (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
        float f; memcpy(&f, &bits, sizeof(f)); *number = f;
    } else if (type == fourcc("ui8 ") && value->size == 1) {
        *number = b[0];
    } else if (type == fourcc("ui16") && value->size == 2) {
        *number = (uint16_t)b[0] << 8 | b[1];
    } else if (type == fourcc("ui32") && value->size == 4) {
        *number = (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 | (uint32_t)b[2] << 8 | b[3];
    } else if (value->size == 2 && ((type >> 16) == 0x7370 || (type >> 16) == 0x6670)) {
        int integerBits = hex_digit((type >> 8) & 0xff), fractionBits = hex_digit(type & 0xff);
        bool signedValue = (type >> 16) == 0x7370;
        if (integerBits < 0 || fractionBits < 0 || integerBits + fractionBits != (signedValue ? 15 : 16)) return false;
        uint16_t raw = (uint16_t)b[0] << 8 | b[1];
        *number = ldexp(signedValue ? (double)(int16_t)raw : (double)raw, -fractionBits);
    } else return false;
    return isfinite(*number);
}
