`ifndef __TOP__
`define __TOP__

/*
file: MCU Core top, five stage pipeline MCU core
author: fujie
time: 2023年 5月 6日 星期六 16时03分58秒 CST
*/
`include "definitions.vh"
// `include "pipelineIF.v"
`include "pipelineIF_withFIFO.v"
`include "pipelineID.v"
`include "pipelineEXE.v"
// `include "pipelineMEM.v"
`include "pipelineMEM_withloadstore.v"
`include "pipelineWB.v"
`include "regfile.v"
`include "hazard.v"

`define DIFFTEST

module top(
    input  wire        clk,
    input  wire        resetn,
    // signals used by difftest
    `ifdef DIFFTEST
    output wire [31:0] pc,
    input  wire [63:0] instr,
    output wire [31:0] id_instr,
    output wire [31:0] imem_addr,
    output wire        commit_en
    `endif
    // signals used by difftest
);

    `ifdef DIFFTEST
    // instruction commit
    reg resetn_d, resetn_d_d;
    reg commit_en_exe, commit_en_mem, commit_en_wb, commit_en_delay;
    wire commit_en_id;
    assign id_instr=instruction_f_o;
    // TODO: add stall logic consideration for instruction commit

    always @(posedge clk ) begin 
        resetn_d <= resetn;
        resetn_d_d <= resetn_d;
    end

    assign commit_en_id = ~flush_d_i & resetn_d_d & ~fd_st_f_i;
    assign commit_en    = commit_en_delay;
    always @(posedge clk ) begin 
        if(~resetn) begin
            commit_en_exe <= 0;    
            commit_en_mem <= 0;    
            commit_en_wb  <= 0;    
            commit_en_delay <= 0;    
        end
        else begin
            commit_en_exe   <= commit_en_id;
            commit_en_mem   <= commit_en_exe;
            commit_en_wb    <= commit_en_mem;
            commit_en_delay <= commit_en_wb;
        end
    end
    // pass pc to top 
    assign pc = pc_instr_delay;
    wire [31:0] pc_instr_d_o; 
    reg  [31:0] pc_instr_e_o, pc_instr_m_o, pc_instr_w_o, pc_instr_delay;
    always @(posedge clk ) begin 
        if(~resetn) begin
            pc_instr_e_o <= 32'h80000000;
            pc_instr_m_o <= 32'h80000000;
            pc_instr_w_o <= 32'h80000000;
            pc_instr_delay <= 32'h80000000;
        end
        else begin
            pc_instr_e_o <= pc_instr_d_o;
            pc_instr_m_o <= pc_instr_e_o;
            pc_instr_w_o <= pc_instr_m_o;
            pc_instr_delay <=pc_instr_w_o;
        end
    end
    `endif
    // =========================================================================
    // =============================== variables ===============================
    // =========================================================================
    // hazard sigals
    wire is_b_d_o;              
    wire is_j_d_o ;             
    wire is_load_d_o;           
    wire is_m_d_o;             
    wire is_d_d_o;
    wire  dst_en_d_o;
    wire fin_w_d_o;          
    wire pre_taken_d_o;         
    wire real_taken_e_o;        
    wire [4:0] r_dst_d_o;       
    wire [4:0] r_src1_d_o;            
    wire [4:0] r_src2_d_o;            
    wire [1:0] src1_sel_d_i;
    wire [1:0] src2_sel_d_i;
    wire fd_st_f_i;           
    wire de_st_d_i;            
    wire em_st_e_i; 
    // IF stage instance signals
    wire [31:0]	instruction_f_o;
    wire        is_compress_d_i;
    // ID stage instance signals
    wire [31:0] redirection_pc_e_o;
    wire        redirection_e_o;
    wire        ptnt_e_i;
    wire [31:0]	redirection_d_o;
    wire [31:0] prediction_pc_d_o;
    wire 	taken_d_o;
    wire [20:0]	alu_op_d_o;
    wire [31:0]	rs1_d_o;
    wire [31:0]	rs2_d_o;
    wire [31:0]	rs2_reg_d_o;
    wire [ 3:0]	dmem_type_d_o;
    wire [31:0]	extended_imm_d_o;
    wire [31:0]	pc_plus4_d_o;
    wire 	reg_write_en_d_o;
    wire [ 4:0]	rd_idx_d_o;
    wire [ 3:0]	resultSrc_d_o;
    wire 	instrIllegal_d_o;
    wire     rs1_depended_h_o;
    wire    jalr_d_o;
    wire    btype_d_o;
    wire    flush_jal_d_o;
    wire [1:0] mul_state_d_o;
    wire    d_advance_d_o;
    wire    d_init_d_o;
    wire    div_last_d_o;
    wire    flush_d_i; 
    wire    fin_d_o;
    wire    sbp_taken_d_o;
    
    // EXE instance
    wire        redirection_e_o;
    wire [31:0] redirection_pc_e_o;      
    wire [31:0]	aluResult_e_o;
    wire [31:0]	alu_calculation_e_o;
    wire [ 3:0]	dMemType_e_o;
    wire [31:0]	extendedImm_e_o;
    wire [31:0]	pcPlus4_e_o;
    wire 	reg_write_en_e_o;
    wire [ 4:0]	rdIdx_e_o;
    wire [ 3:0]	resultSrc_e_o;
    wire 	instrIllegal_e_o;
    wire [31:0] bypass_e_o;
    wire [31:0] rs2_e_o;

    // MEM stage instance signals
    wire [31:0]	mem_read_data_m_o;
    wire [31:0]	alu_result_m_o;
    wire [31:0]	extended_imm_m_o;
    wire [31:0]	pc_plus4_m_o;
    wire 	reg_write_en_m_o;
    wire [ 4:0]	rd_idx_m_o;
    wire [ 3:0]	result_src_m_o;
    wire [31:0] bypass_m_o;
    // WB stage instance signals
    wire 	reg_write_en_w_o;
    wire [ 4:0]	rd_idx_w_o;
    wire [31:0]	write_back_data_w_o;


    // =========================================================================
    // ============================ implementation =============================
    // =========================================================================

    //TODO: delete this when EXE add these signals
    // wire [31:0] redirection_pc_e_i;
    // wire        redirection_e_i;
    // wire        ptnt_e_i;
    
     
    // assign wb_en  = wb_en_d_d_d; // used ass difftest signals
    // reg wb_en_d, wb_en_d_d, wb_en_d_d_d;
    // always @(posedge clk ) begin 
    //     if(~resetn) begin
    //         wb_en_d     <= 1'b0;
    //         wb_en_d_d   <= 1'b0;
    //         wb_en_d_d_d <= 1'b0;
    //     end
    //     else begin
    //         wb_en_d     <= reg_write_en_w_o;
    //         wb_en_d_d   <= wb_en_d;
    //         wb_en_d_d_d <= wb_en_d_d;
    //     end
    // end
    

    
    // pipeline resetn signals
    // IF stage instance
    pipelineIF_withFIFO u_pipeline_withFIFO(
        //ports
        .clk            		( clk            		),
        .resetn         		( resetn        		),
        .enable         		( ~ fd_st_f_i      		),
        .redirection_d_i 		( redirection_d_o 		),
        .taken_d_i       		( taken_d_o       		),
        .is_compress_d_i        (is_compress_d_i        ),
        .flush_i                ( flush_jal_d_o         ), // TODO: add flush from EXE
        .instruction_f_o 		( instruction_f_o 		),
        .imemory_output         ( instr[31:0]          ),
        .imem_addr              ( imem_addr)
    );

    // ID stage instance
    pipelineID u_pipelineID(
        //ports
        .clk              		( clk              		),
        .resetn           		( resetn            	),
        .enable           		( ~ de_st_d_i      		),
        .instruction_f_i   		( instruction_f_o  		),
        .redirection_pc_e_i     ( redirection_pc_e_o    ),
        .redirection_e_i        ( redirection_e_o       ),
        .prediction_pc_d_o      ( prediction_pc_d_o     ),
        .ptnt_e_i               ( ptnt_e_i              ),
        .reg_write_en_w_i  		( reg_write_en_w_o    	),
        .rd_idx_w_i        		( rd_idx_w_o       		),
        .write_back_data_w_i 	( write_back_data_w_o 	),
        .rs1_depended_h_i   	( rs1_depended_h_o   	),
        .flush_i                ( flush_d_i             ),
        .src1_sel_d_i           ( src1_sel_d_i          ),
        .src2_sel_d_i           ( src2_sel_d_i          ),
        .stall_i                ( fd_st_f_i             ),
        .bypass_e_o             ( bypass_e_o            ),
        .bypass_m_o             ( bypass_m_o            ),
        .redirection_d_o   		( redirection_d_o   	),
        .taken_d_o         		( taken_d_o         	),
        .sbp_taken_d_o          ( sbp_taken_d_o         ),
        .flush_jal_d_o          ( flush_jal_d_o         ),
        .is_compressed_d_o      ( is_compress_d_i       ),
        .alu_op_d_o         	( alu_op_d_o         	),
        .jalr_d_o               ( jalr_d_o              ),
        .btype_d_o              ( btype_d_o             ),
        .rs1_d_o           		( rs1_d_o           	),
        .rs2_d_o           		( rs2_d_o           	),
        .rs2_reg_d_o           	( rs2_reg_d_o          	),
        .dmem_type_d_o      	( dmem_type_d_o      	),
        .extended_imm_d_o   	( extended_imm_d_o   	),
        .pc_next_d_o        	( pc_plus4_d_o       	),
        .reg_write_en_d_o    	( reg_write_en_d_o    	),
        .rd_idx_d_o         	( rd_idx_d_o         	),
        .result_src_d_o     	( resultSrc_d_o     	),
        .instr_illegal_d_o  	( instrIllegal_d_o  	),
        .is_d_d_o               ( is_d_d_o              ),
        .is_m_d_o               ( is_m_d_o              ),
        .is_b_d_o               ( is_b_d_o              ),
        .is_j_d_o               ( is_j_d_o              ),
        .is_load_d_o            ( is_load_d_o           ),
        .dst_en_d_o             ( dst_en_d_o            ),
        .fin_d_o                ( fin_d_o               ),
        .fin_w_d_o              ( fin_w_d_o             ),
        .pre_taken_d_o          ( pre_taken_d_o         ),
        .r_dst_d_o              ( r_dst_d_o             ),
        .r_src1_d_o             ( r_src1_d_o            ),
        .r_src2_d_o             ( r_src2_d_o            ),
        .mul_state_d_o          ( mul_state_d_o         ),
        .div_last_d_o           ( div_last_d_o          ),
        .d_advance_d_o          ( d_advance_d_o         ),
        .d_init_d_o             ( d_init_d_o            ),
        // DIFFTEST
        `ifdef DIFFTEST
        .pc_instr_d_o           ( pc_instr_d_o          )
        `endif
        // DIFFTEST
        //.CSR_data_d_i           ( CSR_data_c_o          ),
        //.CSR_data_d_o           ( CSR_data_d_o          ),
        //.CSR_addr_d_o           ( CSR_addr_d_o          ),
        //.CSR_addr_d_o_w         ( CSR_addr_d_o_w        )
        
    );

    pipelineEXE u_pipelineEXE(
        //ports
        .clk             		( clk             		),
        .resetn           		( resetn           	    ),
        .st_e_i                 ( em_st_e_i             ),
        .alu_op_d_i        		( alu_op_d_o        	),
        .rs1_d_i          		( rs1_d_o          		),
        .rs2_d_i          		( rs2_d_o          		),
        .rs2_reg_d_i       		( rs2_reg_d_o          	),
        .extended_imm_d_i  		( extended_imm_d_o  	),
        .pc_plus4_d_i      		( pc_plus4_d_o      	),
        .taken_d_i              ( sbp_taken_d_o         ),
        .prediction_pc_d_i      ( prediction_pc_d_o     ),
        .flush_e_i              ( 1'b0                  ),
        .redirection_e_o        ( redirection_e_o       ),
        .redirection_pc_e_o     ( redirection_pc_e_o    ),
        .jalr_d_i               ( jalr_d_o              ),
        .btype_d_i              ( btype_d_o             ),
        .dmem_type_d_i     		( dmem_type_d_o     	),
        .reg_write_en_d_i   	( reg_write_en_d_o   	),
        .rd_idx_d_i        		( rd_idx_d_o        	),
        .result_src_d_i    		( resultSrc_d_o    		),
        .instr_illegal_d_i 		( instrIllegal_d_o 		),
        .d_advance_d_o          ( d_advance_d_o         ),
        .d_init_d_o             ( d_init_d_o            ),
        .mul_state_d_o          ( mul_state_d_o         ),
        .div_last_d_o           ( div_last_d_o          ),
        .alu_result_e_o    		( aluResult_e_o    		),
        .alu_calculation_e_o   	( alu_calculation_e_o	),
        .dmem_type_e_o     		( dMemType_e_o     		),
        .rs2_e_o                ( rs2_e_o               ),
        .extended_imm_e_o  		( extendedImm_e_o  		),
        .pc_plus4_e_o      		( pcPlus4_e_o      		),
        .reg_write_en_e_o   	( reg_write_en_e_o   		),
        .rd_idx_e_o        		( rdIdx_e_o        		),
        .result_src_e_o    		( resultSrc_e_o    		),
        .instr_illegal_e_o 		( instrIllegal_e_o 		),
        .real_taken_e_o         ( real_taken_e_o        ),
        .bypass_e_o             ( bypass_e_o            )
        //.CSR_wen_e_o            ( CSR_wen_e_o           )
    );

    // MEM stage instance
    pipelineMEM_withloadstore u_pipelineMEM_withloadstore(
        //ports
        .clk             		( clk             		),
        .resetn           		( resetn           		),
        .rs2_e_i                ( rs2_e_o               ),
        .alu_result_e_i    		( aluResult_e_o    		),
        .alu_calculation_e_i   	( alu_calculation_e_o  	),
        .dmem_type_e_i     		( dMemType_e_o     		),
        .extended_imm_e_i  		( extendedImm_e_o  		),
        .pc_plus_e_i      		( pcPlus4_e_o      		),
        .reg_write_en_e_i   	( reg_write_en_e_o 		),
        .rd_idx_e_i        		( rdIdx_e_o        		),
        .result_src_e_i    		( resultSrc_e_o    		),
        .mem_read_data_m_o  	( mem_read_data_m_o  	),
        .alu_result_m_o    		( alu_result_m_o    	),
        .extended_imm_m_o  		( extended_imm_m_o  	),
        .pc_plus_m_o      		( pc_plus4_m_o      	),
        .reg_write_en_m_o   	( reg_write_en_m_o   	),
        .rd_idx_m_o        		( rd_idx_m_o        	),
        .result_src_m_o    		( result_src_m_o    	),
        .bypass_m_o             ( bypass_m_o            )
    );

    // WB stage instance
    pipelineWB u_pipelineWB(
        //ports
        .clk             		( clk             		),
        .resetn           		( resetn           		),
        .alu_result_m_i     	( alu_result_m_o     	),
        .mem_read_data_m_i  	( mem_read_data_m_o   	),
        .extended_imm_m_i   	( extended_imm_m_o   	),
        .pc_plus4_m_i       	( pc_plus4_m_o       	),
        .reg_write_en_m_i   	( reg_write_en_m_o    	),
        .rd_idx_m_i          	( rd_idx_m_o        	),
        .result_src_m_i     	( result_src_m_o     	),
        .reg_write_en_w_o    	( reg_write_en_w_o    	),
        .rd_idx_w_o          	( rd_idx_w_o         	),
        .write_back_data_w_o 	( write_back_data_w_o 	)
    );

    hazard hu(
        .is_b                   ( is_b_d_o              ),
        .is_j                   ( is_j_d_o              ),
        .is_load                ( is_load_d_o           ),
        .is_m                   ( is_m_d_o              ),
        .is_d                   ( is_d_d_o              ),
        .dst_en                 ( dst_en_d_o            ),
        .fin                    ( fin_w_d_o             ),
        .pre_taken              ( pre_taken_d_o         ),
        .real_taken             ( real_taken_e_o        ),
        .r_dst                  ( r_dst_d_o             ),
        .r_src1                 ( r_src1_d_o            ),
        .r_src2                 ( r_src2_d_o            ),
        .src1_sel               ( src1_sel_d_i          ),
        .src2_sel               ( src2_sel_d_i          ),
        .f_cmiss                ( 1'b0                  ),
        .m_cmiss                ( 1'b0                  ),
        .f_arrival              ( 1'b0                  ),
        .m_arrival              ( 1'b0                  ),
        .fd_st                  ( fd_st_f_i             ),
        .de_st                  ( de_st_d_i             ),
        .em_st                  ( em_st_e_i             ),
        .mw_st                  (),
        .ptnt_e_i               ( ptnt_e_i              ),
        .rs1_depended_h_o       ( rs1_depended_h_o      ),
        .flush_o                ( flush_d_i             ),
        .rstn                   ( resetn                ),
        .clk                    ( clk                   )
    );

   /* CSR csru(
        .raddr                  ( CSR_addr_d_o_w        ),
        .waddr                  ( CSR_addr_d_o          ),
        .wdata                  ( aluResult_e_o         ),
        .resetn                 ( resetn                ),
        .clk                    ( clk                   ),
        .wen                    ( CSR_wen_e_o           ),
        .rdata                  ( CSR_data_c_o          )
    );*/

endmodule
`endif
