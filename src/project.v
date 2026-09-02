`default_nettype none

module tt_um_mc14500b_soc_extended (
    input  wire [7:0] ui_in,    // Run Mode: Parallel Input / Prog Mode: Instruction Byte
    output wire [7:0] uo_out,   // Output Port ([6:0]=Latched/RAM outputs, [7]=Hardware PWM Output)
    input  wire [7:0] uio_in,   // [7]=prog_mode, [6]=prog_we, [5:0]=prog_addr
    output wire [7:0] uio_out,  // Status outputs: PC, Write Enable, Breakpoint Flag
    output wire [7:0] uio_oe,   // Dynamic IO direction control
    input  wire       ena,      // Tiny Tapeout project enable
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

    // =========================================================================
    // 1. Memory and Programming Registers
    // =========================================================================
    reg [7:0] prog_memory [0:63]; // 64-Byte Program RAM
    reg [15:0] ram_bank;          // Registers 0-7: Local RAM, 8-15: Peripheral Map
    reg [5:0]  pc;                // Program Counter
    reg [7:0]  r_ext_out;         // Core Output Mirror

    // Programming Signals
    wire prog_mode = uio_in[7];
    wire prog_we   = uio_in[6];
    wire [5:0] prog_addr = uio_in[5:0]; 

    // Core Instruction Decoding
    wire [7:0] current_instruction = prog_memory[pc];
    wire [3:0] opcode  = current_instruction[7:4];
    wire [3:0] operand = current_instruction[3:0];

    // Read Data Selection
    wire core_data_in;
    wire core_rr;
    wire core_write_en;
    wire core_data_out;
    wire core_flag_f;
    reg  r_skip;

    reg r_rr, r_oen, r_ien;
    wire actual_data = core_data_in & r_ien;

    // =========================================================================
    // 2. Hardware Extensions & Peripheral Registers
    // =========================================================================
    
    // --- Feature 1: Edge Detector on ui_in[0] ---
    reg ui_in0_d;
    reg edge_flag;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_in0_d  <= 1'b0;
            edge_flag <= 1'b0;
        end else begin
            ui_in0_d <= ui_in[0];
            if (ui_in[0] && !ui_in0_d) begin
                edge_flag <= 1'b1; // Latch rising edge
            end else if (core_write_en && (operand == 4'h8) && core_data_out) begin
                edge_flag <= 1'b0; // Clear on writing 1 to RAM index 8
            end
        end
    end

    // --- Feature 2: Configurable Clock Divider (Slow-Clock Gate) ---
    reg [19:0] slow_counter;
    reg        use_slow_clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slow_counter  <= 20'd0;
            use_slow_clk  <= 1'b0;
        end else begin
            slow_counter <= slow_counter + 1'b1;
            if (core_write_en && (operand == 4'h9)) begin
                use_slow_clk <= core_data_out; // Address 9 toggles slow mode
            end
        end
    end
    wire cpu_clk_step = use_slow_clk ? (slow_counter == 20'd0) : 1'b1;

    // --- Feature 3: Hardware Countdown Timer ---
    reg [7:0] timer_count;
    wire      timer_expired = (timer_count == 8'h00);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_count <= 8'h00;
        end else if (core_write_en && (operand == 4'hA)) begin
            timer_count <= {timer_count[6:0], core_data_out}; // Shift bit into Address 10
        end else if (!timer_expired && cpu_clk_step) begin
            timer_count <= timer_count - 1'b1;
        end
    end

    // --- Feature 4: Memory Breakpoint Engine ---
    reg [5:0] breakpoint_addr;
    wire      breakpoint_hit = (!prog_mode) && (pc == breakpoint_addr);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            breakpoint_addr <= 6'b111111;
        end else if (core_write_en && (operand == 4'hB)) begin
            breakpoint_addr <= {breakpoint_addr[4:0], core_data_out}; // Shift bit into Address 11
        end
    end

    // --- Feature 5: Dedicated Bit-Addressable Output Latch Array ---
    reg [7:0] latched_uo_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_uo_out <= 8'h00;
        end else if (core_write_en && (operand == 4'hC)) begin
            latched_uo_out <= {latched_uo_out[6:0], core_data_out}; // Shift bit into Address 12
        end
    end

    // --- Base Feature: 8-Bit Hardware PWM Generator ---
    reg [7:0] pwm_counter;
    reg [7:0] pwm_duty_cycle;
    wire      pwm_signal;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 8'h00;
        end else begin
            pwm_counter <= pwm_counter + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_duty_cycle <= 8'h00;
        end else if (core_write_en && (operand == 4'hF)) begin
            pwm_duty_cycle <= {pwm_duty_cycle[6:0], core_data_out}; // Shift bit into Address 15
        end
    end

    assign pwm_signal = (pwm_counter < pwm_duty_cycle);

    // =========================================================================
    // 3. Extended RAM Read Data Multiplexing
    // =========================================================================
    // Maps internal peripheral flags back into RAM read space (RAM_BANK[8:15])
    wire [15:0] mapped_ram_bank;
    assign mapped_ram_bank[7:0]  = ram_bank[7:0];
    assign mapped_ram_bank[8]    = edge_flag;       // Read edge flag state
    assign mapped_ram_bank[9]    = use_slow_clk;    // Read clock mode status
    assign mapped_ram_bank[10]   = timer_expired;   // Read 1 if timer hit zero
    assign mapped_ram_bank[11]   = breakpoint_hit;  // Read 1 if PC == breakpoint
    assign mapped_ram_bank[12]   = latched_uo_out[0];
    assign mapped_ram_bank[14:13]= ram_bank[14:13];
    assign mapped_ram_bank[15]   = pwm_signal;

    assign core_data_in = mapped_ram_bank[operand];
    assign core_rr      = r_rr;
    assign core_data_out= r_rr;
    
    // Core Write Enable Calculation
    assign core_write_en = (!prog_mode) && (!r_skip) && (!breakpoint_hit) && 
                           r_oen && ((opcode == 4'h8) || (opcode == 4'h9));
    assign core_flag_f   = (!prog_mode) && (!r_skip) && (opcode == 4'h0);

    // =========================================================================
    // 4. Synchronous Program Memory Writes
    // =========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1) begin
                prog_memory[i] <= 8'h00;
            end
        end else if (prog_mode && prog_we) begin
            prog_memory[prog_addr] <= ui_in;
        end
    end

    // =========================================================================
    // 5. MC14500B Execution Core State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_ext_out <= 8'h00;
            pc        <= 6'b000000;
            ram_bank  <= 16'h0000;
            r_rr      <= 1'b0;
            r_oen     <= 1'b1;
            r_ien     <= 1'b1;
            r_skip    <= 1'b0;
        end else if (prog_mode) begin
            pc <= 6'b000000;
        end else if (cpu_clk_step && !breakpoint_hit) begin
            pc <= pc + 1'b1;
            r_ext_out <= ram_bank[7:0];
            ram_bank[15:8] <= ui_in;

            if (r_skip) begin
                r_skip <= 1'b0;
            end else begin
                case (opcode)
                    4'h0: ; // NOP0 / FLAG O
                    4'h1: r_rr   <= actual_data;           // LD
                    4'h2: r_rr   <= !actual_data;          // LDC
                    4'h3: r_rr   <= r_rr & actual_data;    // AND
                    4'h4: r_rr   <= r_rr & (!actual_data); // ANDC
                    4'h5: r_rr   <= r_rr | actual_data;    // OR
                    4'h6: r_rr   <= r_rr | (!actual_data); // ORC
                    4'h7: r_rr   <= !(r_rr ^ actual_data); // XNOR
                    4'h8: ;                                // STO
                    4'h9: ;                                // STOC
                    4'hA: r_ien  <= actual_data;           // IEN
                    4'hB: r_oen  <= actual_data;           // OEN
                    4'hC: ;                                // JMP
                    4'hD: r_skip <= !r_rr;                 // RTN / SKZ
                    4'hE: ;                                // SKZ
                    4'hF: ;                                // NOPF / FLAG F
                endcase
            end

            // Write to general RAM location (Operand 0 to 7)
            if (core_write_en && (operand < 4'h8)) begin
                ram_bank[operand] <= (opcode == 4'h9) ? !core_data_out : core_data_out;
            end
        end
    end

    // =========================================================================
    // 6. Pin Multiplexing & Output Routing
    // =========================================================================
    // Parallel Outputs: [6:0] displays Latched array outputs; [7] outputs the Hardware PWM signal
    assign uo_out = {pwm_signal, latched_uo_out[6:0]};

    // Extended Status Line Outputs on UIO
    assign uio_out[5:0] = prog_mode ? 6'b000000 : pc;       
    assign uio_out[6]   = prog_mode ? 1'b0 : breakpoint_hit; // High when PC hits breakpoint address
    assign uio_out[7]   = prog_mode ? 1'b0 : core_write_en;  
    
    // Dynamic Pin Directions: Input mode during Programming, Output mode during Run
    assign uio_oe = prog_mode ? 8'b00000000 : 8'b11111111;   

endmodule
