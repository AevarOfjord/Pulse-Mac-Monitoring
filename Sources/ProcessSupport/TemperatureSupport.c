#include "ProcessSupport.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

// Read-only Apple-vendor HID thermal events. These entry points are not a
// stable public temperature API, so resolve them at runtime and fail closed.
typedef CFTypeRef (*CreateClient)(CFAllocatorRef);
typedef void (*SetMatching)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*CopyServices)(CFTypeRef);
typedef CFTypeRef (*CopyProperty)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*CopyEvent)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*GetFloat)(CFTypeRef, int32_t);
typedef uint64_t (*GetRegistryID)(CFTypeRef);

struct PulseTemperatureReader {
    CreateClient create;
    SetMatching match;
    CopyServices services;
    CopyProperty property;
    CopyEvent event;
    GetFloat value;
    GetRegistryID registry_id;
    CFTypeRef client;
    CFArrayRef cached_services;
    double discovered_at;
    int supported;
};

PulseTemperatureReader *pulse_temperature_create(void) {
    PulseTemperatureReader *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->create = (CreateClient)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
    r->match = (SetMatching)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
    r->services = (CopyServices)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
    r->property = (CopyProperty)dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
    r->event = (CopyEvent)dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyEvent");
    r->value = (GetFloat)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    r->registry_id = (GetRegistryID)dlsym(RTLD_DEFAULT, "IOHIDServiceClientGetRegistryID");
    r->supported = r->create && r->match && r->services && r->property && r->event && r->value;
    return r;
}

void pulse_temperature_reset(PulseTemperatureReader *r) {
    if (!r) return;
    if (r->cached_services) CFRelease(r->cached_services);
    r->cached_services = NULL;
}

void pulse_temperature_destroy(PulseTemperatureReader *r) {
    if (!r) return;
    pulse_temperature_reset(r);
    if (r->client) CFRelease(r->client);
    free(r);
}

int pulse_temperature_read(PulseTemperatureReader *r, PulseTemperatureSensor *buffer,
                           int capacity, uint32_t *discovered, double uptime) {
    if (discovered) *discovered = 0;
    if (!r || !r->supported) return -2;
    if (!buffer || capacity <= 0) return -1;
    if (!r->client) {
        r->client = r->create(kCFAllocatorDefault);
        if (!r->client) return -1;
        int page = 0xff00, usage = 5;
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        if (!p || !u) {
            if (p) CFRelease(p);
            if (u) CFRelease(u);
            CFRelease(r->client); r->client = NULL;
            return -1;
        }
        const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
        const void *values[] = {p, u};
        CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!matching) { CFRelease(p); CFRelease(u); CFRelease(r->client); r->client = NULL; return -1; }
        // Matching changes this client's filter, never a hardware property.
        r->match(r->client, matching);
        CFRelease(matching); CFRelease(p); CFRelease(u);
    }
    if (!r->cached_services || uptime < r->discovered_at || uptime - r->discovered_at >= 60) {
        pulse_temperature_reset(r);
        r->cached_services = r->services(r->client);
        r->discovered_at = uptime;
    }
    if (!r->cached_services) return -1;
    CFIndex total = CFArrayGetCount(r->cached_services);
    if (discovered) *discovered = (uint32_t)(total > UINT32_MAX ? UINT32_MAX : total);
    int count = total > capacity ? capacity : (int)total;
    memset(buffer, 0, sizeof(*buffer) * count);
    int events = 0;
    for (int i = 0; i < count; i++) {
        CFTypeRef service = CFArrayGetValueAtIndex(r->cached_services, i);
        PulseTemperatureSensor *sensor = &buffer[i];
        sensor->registry_id = r->registry_id ? r->registry_id(service) : (uint64_t)i + 1;
        if (!sensor->registry_id) sensor->registry_id = (uint64_t)i + 1;
        CFTypeRef name = r->property(service, CFSTR("Product"));
        if (name) {
            if (CFGetTypeID(name) == CFStringGetTypeID() &&
                !CFStringGetCString((CFStringRef)name, sensor->name, sizeof(sensor->name), kCFStringEncodingUTF8)) {
                sensor->name[0] = 0;
            }
            CFRelease(name);
        }
        CFTypeRef event = r->event(service, 15, 0, 0);
        if (event) {
            sensor->celsius = r->value(event, 15 << 16);
            sensor->has_value = 1;
            events++;
            CFRelease(event);
        }
    }
    // Rediscover on the next scheduled read if cached services stopped working.
    if (!events) pulse_temperature_reset(r);
    return count;
}
