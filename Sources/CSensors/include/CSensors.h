#ifndef TC_SENSORS_H
#define TC_SENSORS_H
#include <stdint.h>
#include <stdbool.h>

typedef struct { uint32_t type; uint32_t size; uint8_t bytes[32]; } TCValue;
int32_t tc_open(uint32_t *connection);
void tc_close(uint32_t connection);
int32_t tc_read(uint32_t connection, const char *key, TCValue *value);
int32_t tc_key_at(uint32_t connection, uint32_t index, char key[5]);
bool tc_decode(const TCValue *value, double *number);
#endif
