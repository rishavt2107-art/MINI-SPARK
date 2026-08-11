# Mini Spark SoC

Heterogeneous AI inference SoC — complete RTL-to-GDSII implementation on Cadence gsclib045 45nm.
Architecture inspired by NVIDIA's GB10 Grace-Blackwell module.

## Architecture

- RISC-V RV32I multi-cycle CPU — control plane
- 4x4 weight-stationary INT8 x INT8 -> INT32 MAC array — compute plane
- AXI-Lite interconnect, 1 master / 2 slaves
- Shared 1 KB on-chip SRAM — unified memory
- Workload: GEMV inference kernel, y = a . W

## Signoff Results — gsclib045 45nm @ 100 MHz

| Metric | Value |
|---|---|
| Setup WNS (SS 125C) | +265 ps |
| Hold WNS (FF -40C) | +40 ps |
| Clock skew | 77 ps across 10,121 sinks |
| DRC violations | 0 |
| Antenna violations | 0 |
| Connectivity | Clean |
| Instances | 58,791 (23,391 functional + 35,400 fillers) |
| Chip area | 205,023 um^2 |
| Power | 13.83 mW |

## Layout

![Post-route layout](main_minispark.png)
![Congestion overlay](overlay.png)

## Verification

9 testbenches, 61 directed test cases, all passing in Cadence Xcelium.
Full-chip integration test verifies y = [2,2,2,2] for a = [1,1,1,1], W = 2I.

## Flow

Xcelium (simulation) -> Genus (synthesis) -> Innovus (12-step place and route to GDSII)

## Repository Structure

- `rtl/` — Verilog-2001 source, 10 modules
- `tb/` — 9 testbenches and firmware
- `constraints/` — SDC timing constraints
- `SYNTHESIS/` — Genus script and reports
- `PNR/` — Innovus and MMMC scripts, signoff reports

## Note

GDSII, SPEF, and SDF files are excluded from this repo due to size (15-40 MB each).
They regenerate from the included scripts by re-running the flow.