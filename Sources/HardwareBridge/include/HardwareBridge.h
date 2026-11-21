#ifndef HARDWARE_BRIDGE_H
#define HARDWARE_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct HBContext HBContext;
#define HB_MAX_FANS 8
#define HB_MAX_THERMAL_ZONES 192
/* category: 1 = CPU thermal-zone family, 2 = GPU thermal-zone family. */
typedef struct {
    double value;
    char key[5];
    int category;
} HBThermalZone;
/* Unavailable scalar readings are NAN, never fabricated zeroes. */
typedef struct {
    double gpuPercent;
    double cpuTemperature;
    double gpuTemperature;
    double fanRPM[HB_MAX_FANS];
    int fanCount;
    double cpuWatts;
    double gpuWatts;
    double systemWatts;
    char gpuName[128];
    char errors[1536];
    int thermalZoneCount;
    HBThermalZone thermalZones[HB_MAX_THERMAL_ZONES];
} HBSnapshot;
/* Each context is serial-use; callers must serialize all operations. */
HBContext *HBCreate(void);
void HBDestroy(HBContext *context);
void HBReset(HBContext *context);
void HBSample(HBContext *context, HBSnapshot *snapshot);
/* Decodes the SMC's explicitly typed scalar wire values; unknown types return NAN. */
double HBDecodeSMCValue(uint32_t type, const uint8_t *bytes, size_t size);
#ifdef __cplusplus
}
#endif
#endif
