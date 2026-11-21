#include "HardwareBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FOUR(a,b,c,d) ((uint32_t)(uint8_t)(a)<<24 | (uint32_t)(uint8_t)(b)<<16 | (uint32_t)(uint8_t)(c)<<8 | (uint32_t)(uint8_t)(d))
#define HB_MAX_THERMAL_KEYS 96

/* Undocumented AppleSMC user-client ABI, isolated here. This application sends
 * only read-key-info (9), read-key-by-index (8), and read-bytes (5) commands.
 * No write selector, write command, fan target or fan mode API exists here. */
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCLimits limits;
    SMCInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCPacket;
_Static_assert(sizeof(SMCPacket) == 80, "AppleSMC packet ABI changed");
_Static_assert(offsetof(SMCPacket, bytes) == 48, "AppleSMC payload offset changed");
typedef struct { uint32_t key; SMCInfo info; } SMCKey;

/* Undocumented libIOReport ABI. Every function pointer is checked before use.
 * Copy/Create results are owned and released. ChannelGet functions borrow.
 * Keeping the library loaded until after its CF objects have been released is
 * required because their deallocators may live in libIOReport. */
typedef CFDictionaryRef (*ReportCopyGroup)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef CFTypeRef (*ReportSubscribe)(CFAllocatorRef, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*ReportSamples)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*ReportDelta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*ReportString)(CFDictionaryRef);
typedef int64_t (*ReportInteger)(CFDictionaryRef, int);
struct HBContext {
    io_connect_t smc;
    io_service_t gpu;
    SMCKey cpuZones[HB_MAX_THERMAL_KEYS], gpuZones[HB_MAX_THERMAL_KEYS];
    size_t cpuZoneCount, gpuZoneCount;
    SMCKey fans[HB_MAX_FANS], systemPower;
    int fanCount;
    void *reportLibrary;
    ReportCopyGroup copyGroup;
    ReportSubscribe subscribe;
    ReportSamples samples;
    ReportDelta delta;
    ReportString channelName, unitLabel;
    ReportInteger integer;
    CFTypeRef subscription;
    CFMutableDictionaryRef subscribedChannels;
    CFDictionaryRef previous;
    uint64_t previousTime;
    int gpuEnergyObserved;
    mach_timebase_info_data_t timebase;
    char errors[1536];
};

static void append_error(char *buffer, size_t capacity, const char *format, ...) {
    size_t used = strlen(buffer);
    if (used + 2 >= capacity) return;
    if (used) buffer[used++] = '\n';
    va_list args; va_start(args, format);
    vsnprintf(buffer + used, capacity - used, format, args);
    va_end(args);
}
static uint32_t fourcc(const char *text) { return FOUR(text[0], text[1], text[2], text[3]); }
static void cf_string(CFStringRef string, char *out, size_t count) {
    out[0] = 0;
    if (string && CFGetTypeID(string) == CFStringGetTypeID())
        CFStringGetCString(string, out, (CFIndex)count, kCFStringEncodingUTF8);
}

double HBDecodeSMCValue(uint32_t type, const uint8_t *bytes, size_t size) {
    if (!bytes) return NAN;
    if (type == FOUR('f','l','t',' ') && size == 4) {
        /* Apple Silicon SMC flt values use the host's little-endian IEEE754. */
        uint32_t bits = (uint32_t)bytes[0] | (uint32_t)bytes[1]<<8 | (uint32_t)bytes[2]<<16 | (uint32_t)bytes[3]<<24;
        float value; memcpy(&value, &bits, sizeof(value));
        return isfinite(value) ? value : NAN;
    }
    if ((type == FOUR('u','i','8',' ') && size == 1) ||
        (type == FOUR('u','i','1','6') && size == 2) ||
        (type == FOUR('u','i','3','2') && size == 4)) {
        uint32_t value = 0;
        for (size_t i = 0; i < size; ++i) value = (value << 8) | bytes[i];
        return value;
    }
    /* SMC fixed-point type suffix stores the number of fractional bits in hex. */
    if (size == 2 && (type >> 16 == FOUR(0,0,'f','p') || type >> 16 == FOUR(0,0,'s','p'))) {
        char suffix = (char)type;
        int bits = suffix >= '0' && suffix <= '9' ? suffix - '0' :
                   suffix >= 'a' && suffix <= 'f' ? suffix - 'a' + 10 : -1;
        if (bits < 0) return NAN;
        uint16_t raw = (uint16_t)bytes[0]<<8 | bytes[1];
        double value = type >> 24 == 's' ? (int16_t)raw : raw;
        return ldexp(value, -bits);
    }
    return NAN;
}

static kern_return_t smc_call(HBContext *context, const SMCPacket *input, SMCPacket *output) {
    size_t size = sizeof(*output);
    memset(output, 0, sizeof(*output));
    kern_return_t result = IOConnectCallStructMethod(context->smc, 2, input, sizeof(*input), output, &size);
    if (result != KERN_SUCCESS) return result;
    return size == sizeof(*output) && output->result == 0 ? KERN_SUCCESS : kIOReturnNotFound;
}
static int smc_info(HBContext *context, uint32_t key, SMCKey *cached) {
    SMCPacket input = {0}, output;
    input.key = key; input.command = 9;
    if (smc_call(context, &input, &output) != KERN_SUCCESS || output.info.size == 0 || output.info.size > 32) return 0;
    cached->key = key; cached->info = output.info;
    return 1;
}
static double smc_read(HBContext *context, const SMCKey *cached) {
    if (!context->smc || !cached->key) return NAN;
    SMCPacket input = {0}, output;
    input.key = cached->key; input.info = cached->info; input.command = 5;
    if (smc_call(context, &input, &output) != KERN_SUCCESS) return NAN;
    return HBDecodeSMCValue(cached->info.type, output.bytes, cached->info.size);
}
static void initialize_smc(HBContext *context) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { append_error(context->errors, sizeof(context->errors), "SMC service unavailable on this Mac."); return; }
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &context->smc);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS) {
        context->smc = 0;
        append_error(context->errors, sizeof(context->errors), "SMC access failed (0x%08x)%s.", status,
                     status == kIOReturnNotPermitted ? "; macOS or the process sandbox denied access" : "");
        return;
    }
    SMCKey countKey = {0};
    if (smc_info(context, fourcc("#KEY"), &countKey)) {
        double count = smc_read(context, &countKey);
        /* Bounded enumeration runs once per context, never in the sample loop. */
        if (isfinite(count) && count > 0 && count <= 65536) {
            for (uint32_t i = 0; i < (uint32_t)count; ++i) {
                SMCPacket input = {0}, output;
                input.command = 8; input.index = i;
                if (smc_call(context, &input, &output) != KERN_SUCCESS) continue;
                uint32_t prefix = output.key >> 16;
                if (prefix == FOUR(0,0,'T','p') && context->cpuZoneCount < HB_MAX_THERMAL_KEYS) {
                    if (smc_info(context, output.key, &context->cpuZones[context->cpuZoneCount])) ++context->cpuZoneCount;
                } else if (prefix == FOUR(0,0,'T','g') && context->gpuZoneCount < HB_MAX_THERMAL_KEYS) {
                    if (smc_info(context, output.key, &context->gpuZones[context->gpuZoneCount])) ++context->gpuZoneCount;
                }
            }
        }
    }
    SMCKey fanCount = {0};
    if (smc_info(context, fourcc("FNum"), &fanCount)) {
        double count = smc_read(context, &fanCount);
        if (isfinite(count) && count >= 0 && count <= HB_MAX_FANS) context->fanCount = (int)count;
        for (int i = 0; i < context->fanCount; ++i) {
            char key[5]; snprintf(key, sizeof(key), "F%dAc", i);
            smc_info(context, fourcc(key), &context->fans[i]);
        }
    }
    /* PSTR is the SMC's total system power sensor, not a sum of CPU/GPU rails. */
    smc_info(context, fourcc("PSTR"), &context->systemPower);
}

static void initialize_report(HBContext *context) {
    context->reportLibrary = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!context->reportLibrary) { append_error(context->errors, sizeof(context->errors), "IOReport library unavailable; CPU/GPU power unavailable."); return; }
#define LOAD(field, symbol) context->field = dlsym(context->reportLibrary, symbol)
    LOAD(copyGroup, "IOReportCopyChannelsInGroup");
    LOAD(subscribe, "IOReportCreateSubscription");
    LOAD(samples, "IOReportCreateSamples");
    LOAD(delta, "IOReportCreateSamplesDelta");
    LOAD(channelName, "IOReportChannelGetChannelName");
    LOAD(unitLabel, "IOReportChannelGetUnitLabel");
    LOAD(integer, "IOReportSimpleGetIntegerValue");
#undef LOAD
    if (!context->copyGroup || !context->subscribe || !context->samples || !context->delta || !context->channelName || !context->unitLabel || !context->integer) {
        append_error(context->errors, sizeof(context->errors), "IOReport ABI unavailable on this macOS version."); return;
    }
    CFDictionaryRef channels = context->copyGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!channels) { append_error(context->errors, sizeof(context->errors), "IOReport Energy Model channels unavailable."); return; }
    /* Subscribe only to aggregate channels; summing per-core and aggregate
     * counters together would double count energy. */
    CFTypeRef original = CFDictionaryGetValue(channels, CFSTR("IOReportChannels"));
    CFMutableArrayRef wanted = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (original && CFGetTypeID(original) == CFArrayGetTypeID()) {
        CFArrayRef array = original;
        for (CFIndex i = 0; i < CFArrayGetCount(array); ++i) {
            CFTypeRef item = CFArrayGetValueAtIndex(array, i);
            if (CFGetTypeID(item) != CFDictionaryGetTypeID()) continue;
            char name[128]; cf_string(context->channelName(item), name, sizeof(name));
            if (!strcmp(name, "CPU Energy") || !strcmp(name, "GPU Energy")) CFArrayAppendValue(wanted, item);
        }
    }
    CFMutableDictionaryRef selected = CFDictionaryCreateMutableCopy(NULL, 0, channels);
    CFDictionarySetValue(selected, CFSTR("IOReportChannels"), wanted);
    if (CFArrayGetCount(wanted)) context->subscription = context->subscribe(NULL, selected, &context->subscribedChannels, 0, NULL);
    CFRelease(wanted); CFRelease(selected); CFRelease(channels);
    if (!context->subscription || !context->subscribedChannels)
        append_error(context->errors, sizeof(context->errors), "IOReport energy subscription denied or unavailable (the process sandbox can deny this read-only API).");
}

HBContext *HBCreate(void) {
    HBContext *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    mach_timebase_info(&context->timebase);
    context->gpu = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"));
    if (!context->gpu) context->gpu = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"));
    initialize_smc(context);
    initialize_report(context);
    return context;
}
void HBReset(HBContext *context) {
    if (!context) return;
    if (context->previous) CFRelease(context->previous);
    context->previous = NULL; context->previousTime = 0; context->gpuEnergyObserved = 0;
}
void HBDestroy(HBContext *context) {
    if (!context) return;
    HBReset(context);
    if (context->subscription) CFRelease(context->subscription);
    if (context->subscribedChannels) CFRelease(context->subscribedChannels);
    if (context->reportLibrary) dlclose(context->reportLibrary);
    if (context->smc) IOServiceClose(context->smc);
    if (context->gpu) IOObjectRelease(context->gpu);
    free(context);
}
static double sample_temperatures(HBContext *context, const SMCKey *keys, size_t count, int category, HBSnapshot *snapshot) {
    double maximum = NAN;
    for (size_t i = 0; i < count; ++i) {
        double value = smc_read(context, &keys[i]);
        /* Reject obvious sentinel/out-of-range thermal readings. */
        if (isfinite(value) && value > 0 && value < 150) {
            if (!isfinite(maximum) || value > maximum) maximum = value;
            if (snapshot->thermalZoneCount < HB_MAX_THERMAL_ZONES) {
                HBThermalZone *zone = &snapshot->thermalZones[snapshot->thermalZoneCount++];
                zone->value = value; zone->category = category;
                zone->key[0] = (char)(keys[i].key >> 24);
                zone->key[1] = (char)(keys[i].key >> 16);
                zone->key[2] = (char)(keys[i].key >> 8);
                zone->key[3] = (char)keys[i].key; zone->key[4] = 0;
            }
        }
    }
    return maximum;
}
static void sample_gpu(HBContext *context, HBSnapshot *snapshot) {
    strcpy(snapshot->gpuName, "GPU");
    if (!context->gpu) { append_error(snapshot->errors, sizeof(snapshot->errors), "GPU registry service unavailable."); return; }
    CFTypeRef model = IORegistryEntryCreateCFProperty(context->gpu, CFSTR("model"), NULL, 0);
    if (model) {
        if (CFGetTypeID(model) == CFStringGetTypeID()) cf_string(model, snapshot->gpuName, sizeof(snapshot->gpuName));
        else if (CFGetTypeID(model) == CFDataGetTypeID()) {
            size_t count = (size_t)CFDataGetLength(model);
            if (count >= sizeof(snapshot->gpuName)) count = sizeof(snapshot->gpuName) - 1;
            memcpy(snapshot->gpuName, CFDataGetBytePtr(model), count); snapshot->gpuName[count] = 0;
        }
        CFRelease(model);
    }
    CFTypeRef property = IORegistryEntryCreateCFProperty(context->gpu, CFSTR("PerformanceStatistics"), NULL, 0);
    if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
        CFTypeRef utilization = CFDictionaryGetValue(property, CFSTR("Device Utilization %"));
        double value;
        if (utilization && CFGetTypeID(utilization) == CFNumberGetTypeID() && CFNumberGetValue(utilization, kCFNumberDoubleType, &value) && isfinite(value) && value >= 0 && value <= 100)
            snapshot->gpuPercent = value;
    }
    if (property) CFRelease(property);
    if (!isfinite(snapshot->gpuPercent)) append_error(snapshot->errors, sizeof(snapshot->errors), "GPU Device Utilization %% is not published by this driver.");
}
static double joules_per_unit(CFStringRef unit) {
    if (!unit) return NAN;
    if (CFEqual(unit, CFSTR("J"))) return 1;
    if (CFEqual(unit, CFSTR("mJ"))) return 1e-3;
    if (CFEqual(unit, CFSTR("uJ")) || CFEqual(unit, CFSTR("µJ"))) return 1e-6;
    if (CFEqual(unit, CFSTR("nJ"))) return 1e-9;
    return NAN;
}
static void sample_power(HBContext *context, HBSnapshot *snapshot) {
    if (!context->subscription || !context->subscribedChannels) return;
    CFDictionaryRef current = context->samples(context->subscription, context->subscribedChannels, NULL);
    uint64_t now = mach_continuous_time();
    if (!current) { HBReset(context); append_error(snapshot->errors, sizeof(snapshot->errors), "IOReport sample failed."); return; }
    if (!context->previous) {
        context->previous = current; context->previousTime = now;
        append_error(snapshot->errors, sizeof(snapshot->errors), "CPU/GPU power is collecting its first energy baseline."); return;
    }
    double seconds = (double)(now - context->previousTime) * context->timebase.numer / context->timebase.denom / 1e9;
    CFDictionaryRef delta = seconds > 0 ? context->delta(context->previous, current, NULL) : NULL;
    int cpuSeen = 0, gpuSeen = 0;
    if (delta) {
        CFTypeRef channels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
        CFTypeRef absoluteChannels = CFDictionaryGetValue(current, CFSTR("IOReportChannels"));
        if (channels && CFGetTypeID(channels) == CFArrayGetTypeID() && absoluteChannels && CFGetTypeID(absoluteChannels) == CFArrayGetTypeID()) {
            CFArrayRef array = channels, absolute = absoluteChannels;
            for (CFIndex i = 0; i < CFArrayGetCount(array); ++i) {
                CFDictionaryRef channel = CFArrayGetValueAtIndex(array, i);
                if (CFGetTypeID(channel) != CFDictionaryGetTypeID()) continue;
                char name[128]; cf_string(context->channelName(channel), name, sizeof(name));
                int cpu = !strcmp(name, "CPU Energy"), gpu = !strcmp(name, "GPU Energy");
                if (!cpu && !gpu) continue;
                double scale = joules_per_unit(context->unitLabel(channel));
                int64_t energy = context->integer(channel, 0);
                int validBaseline = 0;
                /* A permanently zero/unsupported channel is not evidence of 0 W.
                 * Require a positive absolute energy baseline; a subsequent zero
                 * delta can then legitimately mean an idle component. */
                for (CFIndex j = 0; j < CFArrayGetCount(absolute); ++j) {
                    CFTypeRef raw = CFArrayGetValueAtIndex(absolute, j);
                    if (CFGetTypeID(raw) != CFDictionaryGetTypeID()) continue;
                    CFStringRef rawName = context->channelName(raw), deltaName = context->channelName(channel);
                    if (rawName && deltaName && CFEqual(rawName, deltaName) && context->integer(raw, 0) > 0) { validBaseline = 1; break; }
                }
                double watts = energy * scale / seconds;
                if (gpu && energy > 0 && validBaseline) context->gpuEnergyObserved = 1;
                /* CPU must consume nonzero energy while this process is awake.
                 * Some firmware exposes a positive but permanently frozen CPU
                 * total; never present its zero delta as a measured zero watt.
                 * GPU zero is accepted only after this context observed an
                 * advancing GPU counter, allowing actual GPU idle periods. */
                int advancing = cpu ? energy > 0 : context->gpuEnergyObserved;
                if (validBaseline && advancing && energy >= 0 && isfinite(watts) && watts >= 0 && watts < 2000) {
                    if (cpu) { snapshot->cpuWatts = watts; cpuSeen = 1; }
                    if (gpu) { snapshot->gpuWatts = watts; gpuSeen = 1; }
                }
            }
        }
        CFRelease(delta);
    }
    CFRelease(context->previous); context->previous = current; context->previousTime = now;
    if (!cpuSeen) append_error(snapshot->errors, sizeof(snapshot->errors), "CPU power unavailable: IOReport CPU Energy did not advance or is unsupported (not a measured zero).");
    if (!gpuSeen) append_error(snapshot->errors, sizeof(snapshot->errors), "GPU power unavailable: IOReport GPU Energy or its unit is unsupported.");
}
void HBSample(HBContext *context, HBSnapshot *snapshot) {
    if (!snapshot) return;
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->gpuPercent = snapshot->cpuTemperature = snapshot->gpuTemperature = NAN;
    snapshot->cpuWatts = snapshot->gpuWatts = snapshot->systemWatts = NAN;
    for (int i = 0; i < HB_MAX_FANS; ++i) snapshot->fanRPM[i] = NAN;
    if (!context) { strcpy(snapshot->errors, "Hardware collector allocation failed."); strcpy(snapshot->gpuName, "GPU"); return; }
    snprintf(snapshot->errors, sizeof(snapshot->errors), "%s", context->errors);
    sample_gpu(context, snapshot);
    if (context->smc) {
        snapshot->cpuTemperature = sample_temperatures(context, context->cpuZones, context->cpuZoneCount, 1, snapshot);
        snapshot->gpuTemperature = sample_temperatures(context, context->gpuZones, context->gpuZoneCount, 2, snapshot);
        if (!isfinite(snapshot->cpuTemperature)) append_error(snapshot->errors, sizeof(snapshot->errors), "CPU SMC Tp thermal zones unavailable.");
        if (!isfinite(snapshot->gpuTemperature)) append_error(snapshot->errors, sizeof(snapshot->errors), "GPU SMC Tg thermal zones unavailable.");
        snapshot->fanCount = context->fanCount;
        for (int i = 0; i < context->fanCount; ++i) {
            double rpm = smc_read(context, &context->fans[i]);
            if (isfinite(rpm) && rpm >= 0 && rpm <= 20000) snapshot->fanRPM[i] = rpm;
            else append_error(snapshot->errors, sizeof(snapshot->errors), "Fan %d actual RPM unavailable.", i + 1);
        }
        double watts = smc_read(context, &context->systemPower);
        if (isfinite(watts) && watts >= 0 && watts < 2000) snapshot->systemWatts = watts;
    }
    sample_power(context, snapshot);
}
