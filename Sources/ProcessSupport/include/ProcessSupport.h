#ifndef PULSE_PROCESS_SUPPORT_H
#define PULSE_PROCESS_SUPPORT_H
#include <stdint.h>

typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint32_t uid;
    uint64_t started_microseconds;
    uint64_t cpu_nanoseconds;
    uint64_t resident_bytes;
    uint64_t footprint_bytes;
    uint64_t compressed_bytes;
    uint64_t peak_footprint_bytes;
    int has_usage;
    int has_cpu;
    int has_resident;
    int has_compressed;
    char name[64];
    char path[4096];
} PulseProcessInfo;

int pulse_list_pids(int32_t *buffer, int capacity);
int pulse_read_process(int32_t pid, PulseProcessInfo *info);
int pulse_read_arguments(int32_t pid, char *buffer, int capacity);

typedef struct PulseTemperatureReader PulseTemperatureReader;
typedef struct {
    uint64_t registry_id;
    double celsius;
    int has_value;
    char name[128];
} PulseTemperatureSensor;

PulseTemperatureReader *pulse_temperature_create(void);
void pulse_temperature_destroy(PulseTemperatureReader *reader);
void pulse_temperature_reset(PulseTemperatureReader *reader);
// Returns a sensor count, -1 when unavailable, or -2 for missing API symbols.
int pulse_temperature_read(PulseTemperatureReader *reader, PulseTemperatureSensor *buffer,
                           int capacity, uint32_t *discovered, double uptime);
#endif
