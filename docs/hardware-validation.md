# Native hardware validation

Validated on Apple M1 Pro (16 GPU cores), arm64, macOS 27.2.1 (26B131), on 2026-11-21. This is an original IOKit/CoreFoundation implementation with experimentally verified AppleSMC/libIOReport protocols. The hardware implementation was developed independently; no source was copied, forked or adapted from an open-source monitor.

## Measured readings

| Reading | Native source | Observed result |
|---|---|---|
| GPU busy | IOAccelerator `PerformanceStatistics` → `Device Utilization %` | 0–56%; driver-reported recent utilization |
| CPU temperature | Maximum valid `Tp*` SMC thermal zone | 62–85 °C across idle/build/load checks |
| GPU temperature | Maximum valid `Tg*` SMC thermal zone | 57–67 °C |
| Actual fans | `FNum=2`, `F0Ac`, `F1Ac`, type `flt ` | 0/0 RPM during these checks; valid stopped-fan readings |
| GPU power | IOReport `Energy Model` / `GPU Energy`, unit `nJ`, divided by monotonic elapsed time | 0.69–2.08 W across checks |
| System power | Direct SMC `PSTR`, type `flt ` | 13–30 W; firmware's system-total DC reading, not AC wall power or CPU+GPU sum |
| CPU power | IOReport `CPU Energy`, unit `mJ` | **Unavailable on this running host: frozen counter.** Explicit diagnostic, never fabricated 0 W. |

Thermal readings identify SMC zone families and their maximum, not a verified one-to-one physical-core mapping or official Apple junction-temperature API. Discovered CPU keys:

`Tp00 Tp01 Tp02 Tp04 Tp05 Tp06 Tp08 Tp09 Tp0A Tp0C Tp0D Tp0E Tp0G Tp0H Tp0I Tp0K Tp0L Tp0M Tp0O Tp0P Tp0Q Tp0S Tp0T Tp0U Tp0W Tp0X Tp0Y Tp0a Tp0b Tp0c`.

GPU keys: `Tg04 Tg05 Tg0C Tg0D`. All 30 CPU and 4 GPU zones are also emitted individually with stable IDs such as `sensor.Tp01` and `sensor.Tg05`, alongside the maxima. Each cached zone is read once per sample; the same value feeds its individual row and aggregate. All were readable `flt ` scalar sensors. Discovery is bounded to 65,536 keys and cached once per context; samples read cached metadata and use no subprocesses.

## CPU power investigation: unmet requirement

`CPU Energy` absolute count remained **957953558 mJ** across separate probes several minutes apart. A controlled three-second four-thread floating-point load produced identical before/after CPU counts and zero CPU delta while GPU Energy advanced. CPU raw element payload also stayed unchanged across probes. A positive historical total therefore does not establish a valid current measurement.

The complete Energy Model group was inspected, not only the aggregate CPU label. All channels below had zero deltas under the controlled load:

- `EACC_CPU0`, `EACC_CPU1`.
- `PACC0_CPU0`–`PACC0_CPU3`, `PACC1_CPU0`–`PACC1_CPU3`.
- `EACC_CPM`, `PACC0_CPM`, `PACC1_CPM`.
- `EACC_CPU`, `PACC0_CPU`, `PACC1_CPU`, `CPU Energy`.
- `ECPUDTL00`–`ECPUDTL04`, `ECPUDTL10`–`ECPUDTL14`.
- `PCPUDTL00`–`PCPUDTL0e`, `PCPUDTL10`–`PCPUDTL1e`, `PCPUDTL20`–`PCPUDTL2e`, `PCPUDTL30`–`PCPUDTL3e` (hex suffixes).
- `PCPU1DTL00`–`PCPU1DTL0e`, `PCPU1DTL10`–`PCPU1DTL1e`, `PCPU1DTL20`–`PCPU1DTL2e`, `PCPU1DTL30`–`PCPU1DTL3e` (hex suffixes).
- `GPU0`, `GPU SRAM0`, `ANE0`, `ISP0`, `AVE0`, `MSR0`, `DCS0`, `DRAM0`, `AMCC0`.
- `apciec0 Energy`, `apciec1 Energy`, `apciec2 Energy`, `PCIe Port 0 Energy`, `PCIe Port 1 Energy` (unit `uJ`).

All CPU/PMGR channels above used `mJ`. Separate AGX `GPU Energy` used `nJ` and advanced by 661143960 nJ over one three-second load probe and 2134075930 nJ over another. These are interval energies; watts divide by actual elapsed seconds.

`powermetrics --samplers cpu_power -n 1 -i 1000` exited 1: `powermetrics must be invoked as the superuser`. No sudo, privileged helper or firmware write was attempted. Opaque SMC power rails were readable but none was guessed to be CPU power. CPU watts remain an unmet requirement on this host; they can appear if the platform/session later publishes advancing CPU energy.

GPU zero watts are allowed only after the current context has observed advancing GPU energy. CPU zero deltas stay unavailable because this awake process consumes CPU energy and this host's counter demonstrably froze. Unknown units, rollback, nonfinite numbers and out-of-range readings stay unavailable. First power sample establishes a baseline.

## Sandbox versus hardware support

The Codex shell sandbox allowed GPU registry reads but denied `IOServiceOpen(AppleSMC)` with `0xe00002e2` (`kIOReturnNotPermitted`) and refused the IOReport subscription. The same compiled read-only probe, with narrowly scoped execution outside that sandbox, read temperatures, fans, GPU watts and PSTR without root. Diagnostics retain this distinction. An App Sandbox entitlement can impose the same restrictions; the intended locally built app does not request it.

## Verification

- Decoder test against stub first produced 4 expected failures: float temperature, fixed-point fan RPM, signed temperature, unsigned count. Implemented decoder passed with 0 failures, including unknown types and short-buffer rejection.
- `clang -Wall -Wextra -Werror` bridge/decoder compile linked only IOKit and CoreFoundation: exit 0.
- Individual-zone regression failed before implementation (`expected bounded individual thermal readings; got 0`), then passed on hardware: 30 CPU + 4 GPU zones, unique keys, bounded valid values, and aggregate maxima exactly matching those same readings (65.53/55.21 °C in that run).
- Frozen-counter regression first exited 3 when historical positive CPU total incorrectly produced 0 W. After requiring advancing CPU delta, the same probe exited 0 and returned `cpuW=nan` plus diagnostic.
- Final unsandboxed three-sample native bridge probe exited 0. Last readings: CPU 71.70 °C, GPU 63.61 °C, fans 0/0 RPM, GPU 0.8068 W, PSTR 18.0965 W, CPU watts unavailable. Hardware sampling CPU time was 2.67–3.35 ms; earlier samples ~3–6 ms. These are short observations, not a long-run memory/energy benchmark.
- `CLANG_MODULE_CACHE_PATH=/tmp/native-hw/clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/native-hw/swift-cache swift build --disable-sandbox --target SystemCollectors --scratch-path /tmp/native-hw/swift-build`: exit 0. SDK/cache warnings and a separately owned BasicCollector warning were present; hardware files produced no compiler warning.

Repeat application-level sampling by building MonitorProbe and running `.build/debug/MonitorProbe 3`. First power baseline is expected empty. Run in the normal terminal or authorize the executable's read-only hardware access outside a tool sandbox; do not use sudo. Development C probes/decoder tests lived in `/tmp/native-hw` and are not shipped application subprocesses.

A throwaway Swift lifecycle harness verified lazy context construction, destruction at reset, fresh discovery on the next sample, repeated-reset safety and final destruction at deinit. Before the reset fix it failed at `reset must destroy stale hardware context`; after the fix all checks passed. It also checked Swift zone IDs, CPU/GPU labels, values and units. The harness substituted only the native bridge so ownership calls were directly observable.

## Lifetime and compatibility

IORegistry objects, SMC connection, CF Copy/Create results, report samples and dynamic library have explicit releases. Swift serializes context access through NSLock; discovery occurs lazily on the sampling caller's queue. Reset destroys the complete context, including connections, registry services, cached sensor metadata, discovery errors and the energy baseline. The next sample performs discovery again, so wake or resumed access can recover instead of retaining stale services or an initial access failure. Private interfaces may change between macOS versions; failures remain visible rather than becoming zeroes. No fan-control method, target RPM write or generic write API exists in the bridge.
