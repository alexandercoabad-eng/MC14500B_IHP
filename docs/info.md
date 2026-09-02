<!---
This file is used to generate your project datasheet.
-->

## How it works

This project implements a complete, self-contained 1-bit Microcontroller System on Chip (SoC) centered around a hardened clone of the iconic 1977 Motorola MC14500B Industrial Control Unit (ICU). Tailored for a **1x1 tile footprint**, this macro design packs an instruction memory, a data register scratchpad, a hardware counter, and a parallel-mapped I/O multiplexer into exactly **146 logic cells** (excluding fill and tap cells). It is target-hardened specifically for the **TTIHP26b (IHP 130 nm BiCMOS SG13G2)** open-silicon shuttle run.

The SoC operates completely autonomously, cycling through an internal, preloaded program layout without needing external microcontrollers or clock-stretching hardware logic to drive its execution pipeline.

### Core Architectural Features:
* **Sub-Core CPU:** Fully independent 1-bit MC14500B CPU running the original 16-opcode Boolean logic Instruction Set Architecture (ISA).
* **Program Counter (PC):** An internal 8-bit sequential stepping address counter register that loops through memory space.
* **On-Chip ROM Program Memory:** 256 Words x 8-bit instruction bus width. Instructions use a split-bus strategy where the upper nibble (`[7:4]`) represents the CPU opcode, and the lower nibble (`[3:0]`) maps the data address operand.
* **On-Chip Data RAM Scratchpad:** 16 independent, single-bit internal static register memory cells (`4'h0` to `4'hF`).

### Memory & I/O Mapping Matrix:
* **Data Registers `4'h0` to `4'h7`:** General-purpose single-bit read/write internal scratchpad data storage registers.
* **Parallel Inputs Integration:** The state of the physical 8-bit chip input bus (`ui_in`) is synced continuously to internal RAM cells `[15:8]` on every clock edge. This allows the 1-bit core to evaluate parallel external signals by calling address spaces `4'h8` to `4'hF`.
* **Parallel Outputs Latch:** The dedicated 8-bit parallel chip output bus (`uo_out`) is driven continuously by the state flags held in internal RAM cells `[7:0]`.
* **Real-Time Signal Monitors:** The bidirectional bus pins (`uio_out`) are configured as driven outputs to act as a built-in hardware debugger. It breaks out the lower 6 bits of the Program Counter, the CPU's internal Result Register (`RR`) state, and the active memory write-strobe clock pulse flag directly to physical pins for real-time logic analyzer probing.

---

## Instruction Set Architecture (ISA) Reference

The SoC processes an 8-bit instruction width grouped into two parts: an **Opcode** (upper 4 bits, `[7:4]`) and a **Data Memory Address Operand** (lower 4 bits, `[3:0]`). The underlying 1-bit core executes the original 16 Motorola MC14500B hardware commands:

| Opcode (Hex) | Mnemonic | Description / Functional Operation |
| :---: | :--- | :--- |
| **`4'h0`** | **NOPO** | **No Operation:** No change in registers. Triggers the hardware external status flag `flag_f`. |
| **`4'h1`** | **LD**   | **Load:** Loads the bit from the addressed memory operand into the Result Register (`RR <= Data`). |
| **`4'h2`** | **LDC**  | **Load Complement:** Loads the inverted bit from memory into the Result Register (`RR <= ~Data`). |
| **`4'h3`** | **AND**  | **Logical AND:** Computes bitwise AND between RR and the memory operand (`RR <= RR & Data`). |
| **`4'h4`** | **ANDC** | **AND Complement:** Computes bitwise AND between RR and the inverted memory operand (`RR <= RR & ~Data`). |
| **`4'h5`** | **OR**   | **Logical OR:** Computes bitwise OR between RR and the memory operand (`RR <= RR \| Data`). |
| **`4'h6`** | **ORC**  | **OR Complement:** Computes bitwise OR between RR and the inverted memory operand (`RR <= RR \| ~Data`). |
| **`4'h7`** | **XNOR** | **Exclusive NOR:** Computes bitwise XNOR between RR and the memory operand (`RR <= ~(RR ^ Data)`). |
| **`4'h8`** | **STO**  | **Store:** Outputs the current state of RR to the addressed data operand. Generates a write strobe pulse. |
| **`4'h9`** | **STOC** | **Store Complement:** Outputs the inverted state of RR to the addressed memory data operand. |
| **`4'hA`** | **IEN**  | **Input Enable:** Loads the bit from the addressed memory operand into the Input Enable Register (`IEN <= Data`). |
| **`4'hB`** | **OEN**  | **Output Enable:** Loads the bit from memory into the Output Enable Register (`OEN <= Data`). |
| **`4'hC`** | **JMP**  | **Jump:** Delegated to external routing/diagnostic flag pins. Triggers the internal hardware status line `flag_o`. |
| **`4'hD`** | **SKPZ** | **Skip Next Instruction if Zero:** If `RR == 0`, the next execution cycle is skipped (`r_skip <= 1`). |
| **`4'hE`** | **ORF**  | **Output Flag Command:** Delegated to diagnostic monitoring flag ports. Triggers status line `flag_o`. |
| **`4'hF`** | **RTN**  | **Return:** Signals execution sequence looping routines. Triggers hardware status output pulse line `flag_o`. |

---

## How to test

The design can be evaluated via behavioral RTL simulations, gate-level netlists, or directly on the physical hardware breakout board once manufactured.

### Behavioral & Gate-Level Simulation (cocotb)
The integrated test framework uses Python-driven `cocotb` test scripts to step through clock events and monitor responses.
1. Navigate your terminal environment into the verification folder: `cd test`
2. Run the automated testing routine: `make`

The test harness sets up a stable 50 MHz simulation clock, executes a hardware reset, streams static bit patterns into the dedicated input pins, and verifies that the resulting parallel output states and instruction stepping lines align with the embedded ROM execution sequence.

### Manual Hardware Testing
1. **Power-Up Reset Sequence:** Drive the `rst_n` pin low, assert a stable running clock frequency source on the `clk` pin, and keep the project select pin `ena` high. Return the `rst_n` pin high to begin the execution sequence.
2. **Signal Stimulus:** Apply static or dynamic digital logic high/low voltages to individual lines across the dedicated parallel input bus (`ui_in`).
3. **Trace Observation:** Monitor the `uo_out` parallel output bus pins using an oscilloscope or logic analyzer. Watch the output registers change state as the internal MCU loops through its ROM program, executes bitwise operations, and stores results back into the parallel latch array.

## External hardware

This SoC is designed to be self-contained for standard verification loops, but can easily interface with basic external digital hardware components:
* **Logic Analyzer / Oscilloscope:** Connect to the bidirectional bus pins (`uio[7:0]`) to capture physical trace files of the internal execution loop, track program counter stepping, and verify timing margins.
* **Parallel Input Switches:** Connect a standard 8-pin DIP switch module or sensor array to the dedicated inputs (`ui[7:0]`) to feed parallel runtime data into the internal register mapping space.
* **LED Driver Array:** Connect low-power LED diagnostic indicators to the dedicated output port pins (`uo[7:0]`) to display register processing states in real time.
