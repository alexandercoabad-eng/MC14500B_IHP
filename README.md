# MC14500B Industrial ICU & Peripheral SoC

An extended System-on-Chip implementation based on the classic **Motorola MC14500B 1-Bit Industrial Control Unit (ICU)**, optimized for high-density physical implementation on the **IHP SG13G2** process node via Tiny Tapeout.

---

## Overview

The MC14500B SoC implements the standard 16-instruction set of the classic 1-bit PLC processor alongside key memory-mapped peripheral modules integrated directly into the address space:

1. **64-Byte Instruction Memory** (Addressable via dynamic programming mode)
2. **Rising Edge Detector** (Memory-mapped peripheral at address `8`)
3. **Programmable Clock Divider / Speed Controller** (Memory-mapped peripheral at address `9`)
4. **Dedicated Parallel Output Latch Array** (Memory-mapped peripheral at address `12` / `0xC`)

---

## Feature Architecture

### Integrated Peripherals

| RAM Address | Function / Register | Description |
|---|---|---|
| `0x0` – `0x7` | General Purpose Registers | Read/Write single-bit internal storage registers. |
| `0x8` | Single-Bit Edge Detector | Captures rising edges on `ui_in[0]`. Clear flag by writing `1`. |
| `0x9` | Clock Divider Control | Sets execution step speed (1 = slow clock mode, 0 = full speed). |
| `0xC` | 8-Bit Output Latch Array | Bitwise dynamic shift latch driving hardware output port `uo_out`. |
| `0xD` – `0xF` | System Inputs | Direct read access to hardware input pins `ui_in[7:0]`. |

---

## Technical Specifications & Physical Design

* **Process Node:** IHP SG13G2 (130 nm)
* **Tile Size:** $1 \times 2$ Block
* **Total Cell Count:** 2,810 standard cells (excluding fill/decap cells)
* **Standard Cell Placement Utilization:** 77.59%
* **Total Routing Wire Length:** 142,821 µm
* **Supported Clock Frequencies:** Full system speed up to PDK target limits with flexible internal slow-step control.

---

## Pinout Map

| Pin | Type | Name | Function |
|---|---|---|---|
| `ui_in[7:0]` | Input | Parallel Data / Instructions | Instruction byte in Program Mode / General inputs in Run Mode. |
| `uo_out[7:0]` | Output | Parallel Output Latch Array | Hardware output pins connected to peripheral register `0xC`. |
| `uio_in[5:0]` | Input | Program Address | Program Counter write target address during programming mode. |
| `uio_in[6]` | Input | Program Write Enable | Pulse high to write byte `ui_in` into `prog_memory[uio_in[5:0]]`. |
| `uio_in[7]` | Input | Program Mode Select | High = Dynamic Instruction Write Mode; Low = Execution Mode. |
| `uio_out[5:0]`| Output | Program Counter (PC) | Real-time 6-bit instruction pointer monitor. |
| `uio_out[7]` | Output | Write Enable Monitor | Real-time execution write enable monitor flag. |

---

## Quick Start & Verification

### Running Tests
To execute functional cocotb simulation tests:
```bash
cd test
make
