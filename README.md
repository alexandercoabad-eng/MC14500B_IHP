![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# MC14500B Extended 1-bit Microcontroller SoC

An advanced, self-contained 1-bit Microcontroller System on Chip (SoC) centered around a hardened clone of the iconic 1977 Motorola MC14500B Industrial Control Unit (ICU). This layout occupies a **1x1 tile footprint** and is target-hardened specifically for the **TTIHP26b (IHP 130 nm BiCMOS SG13G2)** open-source silicon shuttle run.

Unlike a standalone CPU core, this macro design integrates program memory, static scratchpad variable data registers, automated hardware counters, and dedicated parallel I/O port interfaces directly into a single piece of silicon containing exactly **146 logic cells** (excluding fill and tap cells).

---

## Architecture Upgrades: Beyond the 1977 Motorola ICU

This design extends the classic 1-bit Motorola architecture into a fully autonomous microcontroller system:

1. **On-Chip Program ROM (256 Words x 8-bit Width):** The original chip had no internal program storage. This SoC integrates a 256-word synthesized execution ROM. Instructions use an 8-bit format where the upper nibble (`[7:4]`) represents the MC14500B CPU opcode, and the lower nibble (`[3:0]`) maps the target data address operand.
2. **Integrated Program Counter (PC):** The standalone MC14500B lacked internal address indexing or a PC. This design includes an on-chip **8-bit hardware Program Counter register** that automatically increments on every positive clock edge to loop through your ROM application routines.
3. **Internal Data Scratchpad RAM (16 Bits):** Features 16 addressable, single-bit static memory registers (`4'h0` to `4'hF`) allowing fast, internal variable read/write operations.
4. **Dedicated Parallel-to-Serial Port Mapping:**
   * **Parallel Inputs (`ui_in[7:0]`):** Automatically synced directly into the upper half of the internal RAM space (`RAM[15:8]`) on every clock event.
   * **Parallel Outputs (`uo_out[7:0]`):** Driven continuously by the lower half of the internal RAM bank (`RAM[7:0]`), updating your external hardware lines instantly.
5. **Real-Time Hardware Diagnostic Monitors (`uio_out[7:0]`):** Repurposes the bidirectional pins as driven outputs to act as a built-in hardware debugger. It exposes the lower 6 bits of the Program Counter, the core's internal Result Register (`RR`) state, and the active memory write-strobe clock pulse flag directly to physical pins for logic analyzer probing.

---

## Unified SoC Address Mapping Matrix

| Bit Address (Operand) | Target Subsystem | Operational Behavior |
| :--- | :--- | :--- |
| **`4'h0` to `4'h7`** | **Internal Scratchpad RAM** | General-purpose read/write data memory storage cells. |
| **`4'h8` to `4'hF`** | **Parallel Input Port** | Read-only access to physical external pins **`ui_in[7:0]`**. |
| **`4'h0` to `4'h7`** *(on STO/STOC)* | **Parallel Output Port** | Write-only latch routing straight to physical pins **`uo_out[7:0]`**. |

---

## Automated Verification Workflows

The verification suite splits its pipeline tasks to guarantee absolute behavioral correctness and structural layout integrity before submission.

### 1. Behavior RTL Simulation Loop
Driven locally or remotely by a Python-based `cocotb` test harness. 
* Navigate terminal focus into the verification folder: `cd test`
* Clean and fire up the simulation environment: `make clean && make`

The test framework configures a stable 50 MHz clock line, asserts a master reset sequence, injects binary vectors into the parallel inputs, and validates that processing output transitions line up with the embedded ROM sequence.

### 2. Gate-Level Netlist (GL) Layout Hardening
When OpenLane finishes layout compilation, a Gate-Level simulation (`GATES=yes`) verifies the synthesized netlist cells against the physical IHP standard cell simulation libraries.

* **Tooling Fix Note:** Because the IHP PDK simulation model files (`sg13g2_stdcell.v`) use advanced edge-sensitive timing rules wrapped inside `ifnone` constructs, standard open-source tools like Icarus Verilog v12 will crash. 
* To fix this once and for all, the automated **`.github/workflows/gds.yaml`** configuration passes the argument **`IVVP_ARGS: "-gno-specify"`** directly into the testing container. This strips the broken timing parameters out, linking all **146 logic cells** together for a clean pass.

---

## Physical ASIC Configuration Properties
* **Process Technology Node:** IHP 130 nm BiCMOS (SG13G2)
* **Layout Budget Footprint Allocation:** 3x2 Standard Macro Tiles
* **Total Logic Gates Count:** 146 Cell Blocks
* **Target Operational Frequency:** 50 MHz
* **Top-Level Interface Module Name:** `tt_um_mc14500b_soc_extended`
