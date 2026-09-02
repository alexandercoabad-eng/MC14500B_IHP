`default_nettype none

module tt_um_mc14500b_soc_extended (
    input  wire [7:0] ui_in,    // Run Mode: Parallel Input / Prog Mode: Data Byte
    output wire [7:0] uo_out,   // Output Port
    input  wire [7:0] uio_in,   // [7]=prog_mode, [6]=prog_we, [5:0]=prog_addr
    output wire [7:0] uio_out,  // [7]=core_write_en, [6]=core_rr, [5:0]=pc[5:0]
    output wire [7:0] uio_oe,   // Dynamic IO direction
    input  wire       ena,      // Tiny Tapeout project enable
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

    // --- Program Memory (64-byte RAM) ---
    reg [7:0] prog_memory [0:63]; 
    reg [15:0] ram_bank;          
    reg [5:0]  pc;                
    reg [7:0]  r_ext_out;         

    // Control signals
    wire prog_mode = uio_in[7];
    wire prog_we   = uio_in[6];
    wire [5:0] prog_addr = uio_in[5:0]; 

    // Decoding
    wire [7:0] current_instruction = prog_memory[pc];
    wire [3:0] opcode  = current_instruction[7:4];
    wire [3:0] operand = current_instruction[3:0];

    wire core_data_in = ram_bank[operand];
    wire core_rr;
    wire core_write_en;
    wire core_data_out;
    wire core_flag_f;
    reg  r_skip;

    reg r_rr, r_oen, r_ien;
    wire actual_data = core_data_in & r_ien;
    
    assign core_rr       = r_rr;
    assign core_data_out = r_rr;
    assign core_write_en = (!prog_mode) && (!r_skip) && r_oen && ((opcode == 4'h8) || (opcode == 4'h9));
    assign core_flag_f   = (!prog_mode) && (!r_skip) && (opcode == 4'h0);

    // Synchronous memory write & clear logic
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

    // Core execution state machine
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
        end else begin
            pc <= pc + 1'b1;
            r_ext_out <= ram_bank[7:0];
            ram_bank[15:8] <= ui_in;

            if (r_skip) begin
                r_skip <= 1'b0;
            end else begin
                case (opcode)
                    4'h0: ; 
                    4'h1: r_rr   <= actual_data;           
                    4'h2: r_rr   <= !actual_data;          
                    4'h3: r_rr   <= r_rr & actual_data;    
                    4'h4: r_rr   <= r_rr & (!actual_data); 
                    4'h5: r_rr   <= r_rr | actual_data;    
                    4'h6: r_rr   <= r_rr | (!actual_data); 
                    4'h7: r_rr   <= !(r_rr ^ actual_data); 
                    4'h8: ; 
                    4'h9: ; 
                    4'hA: r_ien  <= actual_data;           
                    4'hB: r_oen  <= actual_data;           
                    4'hC: ; 
                    4'hD: r_skip <= !r_rr;                 
                    4'hE: ; 
                    4'hF: ; 
                endcase
            end

            if (core_write_en) begin
                ram_bank[operand] <= (opcode == 4'h9) ? !core_data_out : core_data_out;
            end
        end
    end

    // Outputs
    assign uo_out = r_ext_out;

    assign uio_out[5:0] = prog_mode ? 6'b000000 : pc;       
    assign uio_out[6]   = prog_mode ? 1'b0 : core_rr;       
    assign uio_out[7]   = prog_mode ? 1'b0 : core_write_en; 
    
    assign uio_oe = prog_mode ? 8'b00000000 : 8'b11111111;   

endmodule
