`default_nettype none

module tt_um_mc14500b_soc_extended (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // --- 1. Memory and Programming Registers ---
    reg [7:0] prog_memory [0:63]; 
    reg [15:0] ram_bank;          
    reg [5:0]  pc;                

    wire prog_mode = uio_in[7];
    wire prog_we   = uio_in[6];
    wire [5:0] prog_addr = uio_in[5:0]; 

    wire [7:0] current_instruction = prog_memory[pc];
    wire [3:0] opcode  = current_instruction[7:4];
    wire [3:0] operand = current_instruction[3:0];

    wire core_data_in;
    wire core_rr;
    wire core_write_en;
    wire core_data_out;
    reg  r_skip;

    reg r_rr, r_oen, r_ien;
    wire actual_data = core_data_in & r_ien;

    // --- 2. Compact Peripherals ---
    
    // Feature 1: Edge Detector
    reg ui_in0_d, edge_flag;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_in0_d  <= 1'b0;
            edge_flag <= 1'b0;
        end else begin
            ui_in0_d <= ui_in[0];
            if (ui_in[0] && !ui_in0_d) edge_flag <= 1'b1;
            else if (core_write_en && (operand == 4'h8) && core_data_out) edge_flag <= 1'b0;
        end
    end

    // Feature 2: Compact Clock Divider (Reduced from 20-bit to 12-bit)
    reg [11:0] slow_counter;
    reg        use_slow_clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slow_counter <= 12'd0;
            use_slow_clk <= 1'b0;
        end else begin
            slow_counter <= slow_counter + 1'b1;
            if (core_write_en && (operand == 4'h9)) use_slow_clk <= core_data_out;
        end
    end
    wire cpu_clk_step = use_slow_clk ? (slow_counter == 12'd0) : 1'b1;

    // Feature 3: Hardware Timer
    reg [7:0] timer_count;
    wire      timer_expired = (timer_count == 8'h00);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) timer_count <= 8'h00;
        else if (core_write_en && (operand == 4'hA)) timer_count <= {timer_count[6:0], core_data_out};
        else if (!timer_expired && cpu_clk_step) timer_count <= timer_count - 1'b1;
    end

    // Feature 4: Memory Breakpoint Engine
    reg [5:0] breakpoint_addr;
    wire      breakpoint_hit = (!prog_mode) && (pc == breakpoint_addr);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) breakpoint_addr <= 6'b111111;
        else if (core_write_en && (operand == 4'hB)) breakpoint_addr <= {breakpoint_addr[4:0], core_data_out};
    end

    // Feature 5: Output Latch Array
    reg [7:0] latched_uo_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) latched_uo_out <= 8'h00;
        else if (core_write_en && (operand == 4'hC)) latched_uo_out <= {latched_uo_out[6:0], core_data_out};
    end

    // Base Feature: Hardware PWM
    reg [7:0] pwm_counter, pwm_duty_cycle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pwm_counter <= 8'h00;
        else pwm_counter <= pwm_counter + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pwm_duty_cycle <= 8'h00;
        else if (core_write_en && (operand == 4'hF)) pwm_duty_cycle <= {pwm_duty_cycle[6:0], core_data_out};
    end
    wire pwm_signal = (pwm_counter < pwm_duty_cycle);

    // --- 3. Bus Multiplexing ---
    wire [15:0] mapped_ram_bank;
    assign mapped_ram_bank[7:0]  = ram_bank[7:0];
    assign mapped_ram_bank[8]    = edge_flag;
    assign mapped_ram_bank[9]    = use_slow_clk;
    assign mapped_ram_bank[10]   = timer_expired;
    assign mapped_ram_bank[11]   = breakpoint_hit;
    assign mapped_ram_bank[12]   = latched_uo_out[0];
    assign mapped_ram_bank[14:13]= ram_bank[14:13];
    assign mapped_ram_bank[15]   = pwm_signal;

    assign core_data_in  = mapped_ram_bank[operand];
    assign core_rr       = r_rr;
    assign core_data_out = r_rr;
    
    assign core_write_en = (!prog_mode) && (!r_skip) && (!breakpoint_hit) && 
                           r_oen && ((opcode == 4'h8) || (opcode == 4'h9));

    // --- 4. Program Memory Writes ---
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1) prog_memory[i] <= 8'h00;
        end else if (prog_mode && prog_we) begin
            prog_memory[prog_addr] <= ui_in;
        end
    end

    // --- 5. CPU Execution Core ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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
            ram_bank[15:8] <= ui_in;

            if (r_skip) begin
                r_skip <= 1'b0;
            end else begin
                case (opcode)
                    4'h1: r_rr   <= actual_data;
                    4'h2: r_rr   <= !actual_data;
                    4'h3: r_rr   <= r_rr & actual_data;
                    4'h4: r_rr   <= r_rr & (!actual_data);
                    4'h5: r_rr   <= r_rr | actual_data;
                    4'h6: r_rr   <= r_rr | (!actual_data);
                    4'h7: r_rr   <= !(r_rr ^ actual_data);
                    4'hA: r_ien  <= actual_data;
                    4'hB: r_oen  <= actual_data;
                    4'hD: r_skip <= !r_rr;
                    default: ;
                endcase
            end

            if (core_write_en && (operand < 4'h8)) begin
                ram_bank[operand] <= (opcode == 4'h9) ? !core_data_out : core_data_out;
            end
        end
    end

    // --- 6. Outputs ---
    assign uo_out = {pwm_signal, latched_uo_out[6:0]};
    assign uio_out = prog_mode ? 8'h00 : {core_write_en, breakpoint_hit, pc};
    assign uio_oe  = prog_mode ? 8'b00000000 : 8'b11111111;   

endmodule
