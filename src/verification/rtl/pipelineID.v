`ifndef __PIPELINEID__
`define __PIPELINEID__
/*
* file: ID stage in 5 stage pipeline 
    1. get input from IF stage 
    2. decode the instruction, generate control signals for other components
    3. pass output to EXE stage
main components: 
    1. decoder: decode the instruction 
    2. extending unit: extend imm into 32 bits
    3. static branch predictor: do the static prediction for jump and branch instructions 
    4. compressDecoder: extend the 16 bits compress instruction into 32 bits instruction
author: fujie
time: 2023年 4月28日 星期五 15时52分49秒 CST
*/
`include "definitions.vh"
`include "decoder.v"
`include "staticBranchPredictor.v"
`include "compressDecoder.v"
`include "extendingUnit.v"

module pipelineID(
    input wire clk,
    input wire resetn, // reset signal for ID stage, used for pipeline flush
    input wire enable, // enable signal for ID stage, used for pipeline stall
    // 1. signals passed from IF stage
    input wire [31:0] instruction_f_i, // instruction passed from IF stage
    input wire [31:0] pc_plus4_f_i,      
    input wire [31:0] pc_f_i,      
    // 2. signals passed from WB stage
    input wire        reg_write_en_w_i, // write back to RF enable
    input wire [ 4:0] rd_idx_w_i,   // RF write register index
    input wire [31:0] write_back_data_w_i, // data write to RF in ID 
    // 3. signals passed from Hazard Unit
    input wire        rs1_depended_h_i, // used by `jalr`
    input wire        flush_i,
    
    /* redirection info passed back to IF stage */
    output reg [31:0] redirection_d_o,
    output reg        taken_d_o,
    output reg        flush_jal_d_o,  // flush pipeline because of jal instruction
    /* signals passed to EXE stage */
    // EXE stage signals
    output reg [20:0] alu_op_d_o,         // ALU Operation
    output reg [31:0] rs1_d_o,           // ALU operand 1
    output reg [31:0] rs2_d_o,           // ALU operand 2
    output reg        beq_d_o,           // additional control for ALU
    output reg        blt_d_o,           // additional control for ALU
    output reg        jalr_d_o,         // instruction is branch type instruction
    // MEM stage signals
    output reg [ 2:0] dmem_type_d_o,      // load/store types
    // WB stage signals
    output reg [31:0] extended_imm_d_o,  
    output reg [31:0] pc_plus4_d_o,      
    output reg        reg_write_en_d_o,         
    output reg [ 4:0] rd_idx_d_o,          
    output reg [ 3:0] result_src_d_o,   
    output reg        instr_illegal_d_o   // instruction illegal
    // TODO: bypass at ID, add bypass logic
);
// =========================================================================
// =============================   variables   =============================
// =========================================================================
    wire [ 4:0] rs1_index, rs2_index, rd_index;
    wire       instr_illegal;
    // decoder instance signals
    wire [20:0]	aluOperation_o;
    wire 	    rs1_sel_o;
    wire 	    rs2_sel_o;
    wire [ 2:0]	imm_type_o;
    wire 	    branchBType_o;
    wire 	    branchJAL_o;
    wire 	    branchJALR_o;
    wire [ 2:0]	dmem_type_o;
    wire [ 3:0]	wb_src_o;
    wire 	    wb_en_o;
    wire 	    decoder_instr_illegal;
    // compress decoder instance signals 
    wire [31:0]	instr_o;
    wire 	    is_compressed_o;
    wire 	    compress_instr_illegal;
    wire [31:0] instru_32bits;
    // extending unit instance signals
    wire [31:0]	imm_o;
    // register file  instance signals
    wire [31:0]	rs1_data_o;
    wire [31:0]	rs2_data_o;
    // static branch predictor instance signals
    wire [31:0]	redirection_pc;
    wire 	taken;

// =========================================================================
// ============================ implementation =============================
// =========================================================================

    // index for rd, rs1, rs2
    assign rd_index  = instru_32bits[11: 7];
    assign rs1_index = instru_32bits[19:15];
    assign rs2_index = instru_32bits[24:20];
    assign instr_illegal = decoder_instr_illegal | compress_instr_illegal;
    assign instru_32bits = (is_compressed_o==1'b1) ? instr_o : instruction_f_i;

    // ID stage pipeline register output
    always @(posedge clk ) begin 
        if(~resetn || flush_i) begin
            reg_write_en_d_o  <= 1'b0; 
            result_src_d_o    <= 4'b0;  
            pc_plus4_d_o      <= 32'h0;    
            extended_imm_d_o  <= 32'h0;
            rd_idx_d_o        <= 5'b0;         
            alu_op_d_o        <= 21'h0;      
            jalr_d_o          <= 1'b0;
            rs1_d_o           <= 32'h0;        
            rs2_d_o           <= 32'h0;        
            beq_d_o           <= 1'b0;        
            blt_d_o           <= 1'b0;        
            dmem_type_d_o     <= 3'b0;   
            instr_illegal_d_o <= 1'b0;
            redirection_d_o   <= 32'h0;
            taken_d_o         <= 1'b0;
            flush_jal_d_o     <= 1'b0;
        end
        else if(enable) begin
            reg_write_en_d_o  <= wb_en_o; 
            result_src_d_o    <= wb_src_o;  
            pc_plus4_d_o      <= pc_plus4_f_i;    
            extended_imm_d_o  <= imm_o;
            rd_idx_d_o        <= rd_index; 
            alu_op_d_o        <= aluOperation_o;      
            jalr_d_o          <= branchJALR_o;
            redirection_d_o   <= redirection_pc;
            taken_d_o         <= taken;
            flush_jal_d_o     <= branchJAL_o;
            // choose alu operand source
            if(rs1_sel_o == `RS1SEL_RF) begin
                rs1_d_o <= rs1_data_o;  // alu operand1 from RF
            end
            else begin
                rs1_d_o <= pc_plus4_f_i; // alu source from pc+4
            end
            if(rs2_sel_o == `RS2SEL_RF) begin
                rs2_d_o <= rs2_data_o; // alu operand2 from RF
            end
            else begin
                rs2_d_o <= imm_o;  // alu operand2 from extended_imm 
            end
            dmem_type_d_o     <= dmem_type_o;   
            instr_illegal_d_o <= instr_illegal;
        end
    end



    // decode instance
    decoder u_decoder(
        //ports
        .instruction_i  		( instru_32bits  	),
        .alu_op_o        		( aluOperation_o 		),
        .rs1_sel_o       		( rs1_sel_o       		),
        .rs2_sel_o       		( rs2_sel_o       		),
        .imm_type_o      		( imm_type_o      		),
        .branchBType_o  		( branchBType_o  		),
        .branchJAL_o    		( branchJAL_o    		),
        .branchJALR_o   		( branchJALR_o   		),
        .dmem_type_o     		( dmem_type_o     		),
        .wb_src_o        		( wb_src_o        		),
        .wb_en_o         		( wb_en_o         		),
        .instr_illegal_o 		( decoder_instr_illegal )
    );

    // compress decode instance
    compressDecoder u_compressDecoder(
        //ports
        .instr_i         		( instruction_f_i[15:0]	),
        .instr_o         		( instr_o         		),
        .is_compressed_o 		( is_compressed_o 		),
        .illegal_instr_o 		( compress_instr_illegal)
    );


    // extending unit instance
    extendingUnit u_extendingUnit(
        //ports
        .instr_i    		( instru_32bits ),
        .imm_type_i  		( imm_type_o 		),
        .imm_o      		( imm_o      		)
    );

    // register file instance
    regfile #(
        .REG_DATA_WIDTH     		( 32 		),
        .REGFILE_ADDR_WIDTH 		( 5  		),
        .REGFILE_DEPTH      		( 32 		))
    u_regfile(
        //ports
        .clk_i        		( clk        		    ),
        .resetn_i     		( resetn     		    ),
        .rs1_data_o   		( rs1_data_o   		    ),
        .rs2_data_o   		( rs2_data_o   		    ),
        .rs1_addr_i   		( rs1_index             ),
        .rs2_addr_i   		( rs2_index             ),
        .rd_addr_i    		( rd_idx_w_i  	        ),
        .rd_wr_data_i 		( write_back_data_w_i 	),
        .rd_wr_en_i   		( reg_write_en_w_i   	)
    );

    // static branch predictor instance
    staticBranchPredictor u_staticBranchPredictor(
        //ports
        .branchBType   		( branchBType_o   		),
        .branchJAL     		( branchJAL_o     		),
        .branchJALR    		( branchJALR_o    		),
        .rs1           		( rs1_data_o      		),
        .offset        		( imm_o         		),
        .pc            		( pc_f_i         		),
        .rs1_depended   	( rs1_depended_h_i  	),
        .redirection_pc 	( redirection_pc 		),
        .taken         		( taken         		)
    );

endmodule
`endif
