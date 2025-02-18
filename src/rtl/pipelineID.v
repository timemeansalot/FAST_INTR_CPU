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
// import "DPI-C" function void ebreak(); // add DPI-C
`include "definitions.vh"
`include "decoder.v"
`include "staticBranchPredictor.v"
`include "compressDecoder.v"
`include "extendingUnit.v"
`include "regfile.v"

module pipelineID(
    input wire clk,
    input wire resetn, // reset signal for ID stage, used for pipeline flush
    input wire enable, // enable signal for ID stage, used for pipeline stall
    // 1. signals passed from IF stage
    input wire [31:0] instruction_f_i, // instruction passed from IF stage
    // input wire [31:0] pc_plus4_f_i,      
    // input wire [31:0] pc_f_i,      
    // signals passed from EXE stage 
    input wire [31:0] redirection_pc_e_i, 
    input wire        redirection_e_i,
    input wire        ptnt_e_i, // sbp taken, alu not taken, change pc to pc_next_next
    // 2. signals passed from WB stage
    input wire        reg_write_en_w_i, // write back to RF enable
    input wire [ 4:0] rd_idx_w_i,   // RF write register index
    input wire [31:0] write_back_data_w_i, // data write to RF in ID 
    // 3. signals passed from Hazard Unit
    input wire        rs1_depended_h_i, // used by `jalr`
    input wire        flush_i,
    // signals for bypass
    input wire [1:0]  src1_sel_d_i,src2_sel_d_i,
    input wire [31:0] bypass_e_o,bypass_m_o,
    // stall signals
    input wire        stall_i,
    /* redirection info passed back to IF stage */
    output wire [31:0] redirection_d_o,
    output wire        taken_d_o,
    output reg        flush_jal_d_o,  // flush pipeline because of jal instruction
    output wire        is_compressed_d_o,
    /* signals passed to EXE stage */
    // EXE stage signals
    output reg [1:0]  mul_state_d_o,
    output reg        div_last_d_o,
    output reg        d_advance_d_o,
    output reg        d_init_d_o,
    output reg        fin_d_o,
    output reg [20:0] alu_op_d_o,         // ALU Operation
    output reg [31:0] rs1_d_o,           // ALU operand 1
    output reg [31:0] rs2_d_o,           // ALU operand 2
    output reg [31:0] rs2_reg_d_o,       
    output reg        jalr_d_o,         // instruction is jalr 
    output reg        btype_d_o,         // instruction is branch type instruction
    `ifdef DIFFTEST
    output wire [31:0] pc_instr_d_o,     // instruction PC
    `endif
    output reg [31:0] pc_next_d_o,      // next instruction pc 
    output reg [31:0] prediction_pc_d_o,   // pass to exe stage
    output reg        sbp_taken_d_o,       // pass to exe stage
    // MEM stage signals
    output reg [ 3:0] dmem_type_d_o,      // load/store types
    // WB stage signals
    output reg [31:0] extended_imm_d_o,  
    // output reg [31:0] pc_plus4_d_o,      // TODO: depressed, use pc_next_d_o instead
    output reg        reg_write_en_d_o,         
    output reg [ 4:0] rd_idx_d_o,          
    output reg [ 3:0] result_src_d_o,   
    output reg        instr_illegal_d_o,   // instruction illegal

    //wire output to hazard unit
    output wire is_d_d_o,
    output wire is_m_d_o,
    output wire is_b_d_o,
    output wire is_j_d_o,
    output wire is_load_d_o,
    output wire dst_en_d_o,
    output wire fin_w_d_o,
    output wire pre_taken_d_o,
    output wire [4:0] r_dst_d_o,r_src1_d_o,r_src2_d_o
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
    wire [ 3:0]	dmem_type_o;
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

    // instruction PC related variables
    reg        taken_reg;
    reg  [31:0] pc_taken, pc_instr;
    wire [31:0] pc_next;

    //d&m veriables
    wire d_init;
    wire d_advance;
    wire [1:0] mul_next_state;
    wire [3:0] div_next_state;

    reg [1:0] mul_state;
    reg [3:0] div_state;
    reg div_last;
    reg fin;
// =========================================================================
// ============================ implementation =============================
// =========================================================================

    `ifdef DIFFTEST
    assign pc_instr_d_o = pc_instr; 
    `endif

    // // ebreak 
    // wire [2:0] func3 = instru_32bits[14:12];
    // wire [6:0] func7 = instru_32bits[31:25];
    // wire [6:0] op    = instru_32bits[6:0];
    // reg inst_ebreak =  op[6] &  op[5] &  op[4] & ~op[3] & ~op[2] & ~func3[2] & ~func3[1] & ~func3[0] & ~func7[5] & ~func7[0] & ~instru_32bits[21] &  instru_32bits[20]; // ebreak 断点
    // always @(*) begin
    //   if (inst_ebreak) ebreak();
    // end
    // pass compress info to IF, used by FIFO pop operation
    // assign is_compressed_d_o = resetn_delay & is_compressed_o;
    assign is_compressed_d_o = is_compressed_o;

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
            extended_imm_d_o  <= 32'h0;
            rd_idx_d_o        <= 5'b0;         
            alu_op_d_o        <= 21'h0;      
            jalr_d_o          <= 1'b0;
            btype_d_o         <= 1'b0;
            rs1_d_o           <= 32'h0;        
            rs2_d_o           <= 32'h0;        
            rs2_reg_d_o           <= 32'h0;        
            sbp_taken_d_o     <= 1'b0;
            dmem_type_d_o     <= 4'b0;   
            instr_illegal_d_o <= 1'b0;
            flush_jal_d_o     <= 1'b0;
            fin_d_o           <= 1'b0;
            mul_state_d_o     <= 2'b0;
            d_advance_d_o     <= 1'b0;
            d_init_d_o        <= 1'b0;
            div_last_d_o      <= 1'b0;
            prediction_pc_d_o <= 32'h80000000;
        end
        else if(enable) begin
            reg_write_en_d_o  <= wb_en_o; 
            result_src_d_o    <= wb_src_o;  
            extended_imm_d_o  <= imm_o;
            rd_idx_d_o        <= rd_index; 
            alu_op_d_o        <= aluOperation_o;      
            sbp_taken_d_o     <= taken;
            jalr_d_o          <= branchJALR_o;
            btype_d_o         <= branchBType_o;
            flush_jal_d_o     <= branchJAL_o;
            mul_state_d_o     <= mul_state;
            d_advance_d_o     <= d_advance;
            d_init_d_o        <= d_init;
            div_last_d_o      <= div_last;
            fin_d_o           <= fin;
            prediction_pc_d_o <= redirection_pc;
            // choose alu operand source
            if(rs1_sel_o == `RS1SEL_RF) begin
                rs1_d_o <= ({32{src1_sel_d_i==2'b0}}&rs1_data_o)|
                            ({32{src1_sel_d_i==2'b1}}&bypass_e_o)|
                            ({32{src1_sel_d_i==2'b10}}&bypass_m_o);  // alu operand1 from RF
            end
            else begin
                rs1_d_o <= pc_instr; // alu source from pc+4
            end
            rs2_reg_d_o <= ({32{src2_sel_d_i==2'b0}}&rs2_data_o)|
                        ({32{src2_sel_d_i==2'b1}}&bypass_e_o)|
                        ({32{src2_sel_d_i==2'b10}}&bypass_m_o); // alu operand2 from RF
            if(rs2_sel_o == `RS2SEL_RF) begin
                rs2_d_o <= ({32{src2_sel_d_i==2'b0}}&rs2_data_o)|
                            ({32{src2_sel_d_i==2'b1}}&bypass_e_o)|
                            ({32{src2_sel_d_i==2'b10}}&bypass_m_o); // alu operand2 from RF
            end
            else begin
                rs2_d_o <= imm_o;  // alu operand2 from extended_imm 
            end
            dmem_type_d_o     <= dmem_type_o;   
            instr_illegal_d_o <= instr_illegal;
        end
    end 

    reg resetn_delay;
    always @(posedge clk ) begin 
        resetn_delay <= resetn;
    end
    
    // calculate redirection pc to IF stage
    // assign taken_d_o       = ({~resetn_delay | flush_i} & 1'b1) | ptnt_e_i | redirection_e_i | taken;
    // assign taken_d_o       = ({~resetn_delay} & 1'b1) | ptnt_e_i | redirection_e_i | taken;
    assign taken_d_o       = ~resetn_delay | ptnt_e_i | redirection_e_i | (~flush_i & taken );
    assign redirection_d_o = ({32{~resetn_delay | flush_i}} & 32'h80000000)|
    // assign redirection_d_o = ({32{~resetn | flush_i}} & 32'h80000000)|
                             ({32{ptnt_e_i & ~branchJAL_o}} & pc_next)| // sbp taken, alu not taken
                             ({32{ptnt_e_i &  branchJAL_o}} & redirection_pc)| // sbp taken, alu not taken, following by JAL 
                             ({32{ redirection_e_i}}  & redirection_pc_e_i)| // pc from EXE
                             ({32{~redirection_e_i}}  & redirection_pc);  // pc from SBP

    // calculate instruction pc 
    always @(posedge clk ) begin 
        if(~resetn) begin
            taken_reg <= 1'b1;
            pc_taken  <= 32'h80000000;
        end
        else begin
            taken_reg <= taken_d_o;
            pc_taken  <= redirection_d_o;
        end
    end
    assign pc_next = ({32{ is_compressed_d_o}} & pc_instr + 32'h2)| 
                     ({32{~is_compressed_d_o}} & pc_instr + 32'h4);
    always @(posedge clk ) begin 
        if(~resetn) begin
            pc_instr <= 32'h80000000;    
        end
        else if(taken_reg) begin
            pc_instr <= pc_taken;    
        end 
        else if(~stall_i)begin
            pc_instr <= pc_next;    
        end
    end

    // calculate pc to EXE stage, used to calculate pc_next_next
    always @(posedge clk ) begin 
        pc_next_d_o    <= pc_next;
    end

    //mul&div control signals

    always@(posedge clk)
    begin
        if(~resetn)
        begin
            mul_state<=2'b0;
            div_state<=4'b0;
            div_last<=0;
        end
  
  
        else if(aluOperation_o [10]|aluOperation_o [11]|aluOperation_o [12]|aluOperation_o [13])
        begin
            mul_state<=mul_next_state;
            if(mul_state==2'b11)
            begin
                fin<=1'b1;
            end
            else 
            begin 
                fin<=1'b0;
            end
        end
  
        else if(aluOperation_o [14]|aluOperation_o [15]|aluOperation_o [16]|aluOperation_o [17])
        begin
            if(div_state==4'b1111)
            begin
                div_last<=1'b1;
            end
    
    
            if(div_last)
            begin
        	    div_last<=1'b0;
        	    fin<=1'b1;
            end
            else 
            begin
    	        div_state<=div_next_state; 
      	        fin<=1'b0;
            end
        end
  
        else begin
            fin<=1'b0;
        end
  
    end


    assign div_next_state= div_state+4'b1;
    assign mul_next_state= mul_state+2'b1;

    assign d_init=(aluOperation_o [14]|aluOperation_o [15]|aluOperation_o [16]|aluOperation_o [17])&(div_state==4'b0)&(~div_last);
    assign d_advance=(aluOperation_o [14]|aluOperation_o [15]|aluOperation_o [16]|aluOperation_o [17])&(~(div_state==4'b0));

    assign fin_w_d_o= fin;

    //singals to hazard unit
    assign pre_taken_d_o= taken;
    assign is_d_d_o= aluOperation_o [14]|aluOperation_o [15]|aluOperation_o [16]|aluOperation_o [17];
    assign is_m_d_o=aluOperation_o [10]|aluOperation_o [11]|aluOperation_o [12]|aluOperation_o [13];
    assign is_b_d_o=branchBType_o;
    assign is_j_d_o=branchJAL_o|branchJALR_o;
    assign dst_en_d_o=wb_en_o;
    assign r_dst_d_o=rd_index;
    assign r_src1_d_o=rs1_index;
    assign r_src2_d_o=rs2_index;



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
        .is_load_o              ( is_load_d_o           ),
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
        // DIFFTEST
    );

    // static branch predictor instance
    staticBranchPredictor u_staticBranchPredictor(
        //ports
        .branchBType   		( branchBType_o   		),
        .branchJAL     		( branchJAL_o     		),
        .branchJALR    		( branchJALR_o    		),
        .rs1           		( rs1_data_o      		),
        .offset        		( imm_o         		),
        .pc            		( pc_instr         		),
        .rs1_depended   	( rs1_depended_h_i  	),
        .redirection_pc 	( redirection_pc 		),
        .taken         		( taken         		)
    );

endmodule
`endif

