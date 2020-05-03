//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rafael de Oliveira Calçada
// 
// Create Date: 26.04.2020 23:33:34
// Module Name: csr_file
// Project Name: Steel Core 
// Description: RISC-V Steel Core CSR Register File 
// 
// Dependencies: -
// 
// Version 0.01
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
`include "globals.vh"

module csr_file(

    input wire CLK,
    input wire RESET,
    
    input wire WR_EN,
    input wire [11:0] CSR_ADDR,
    input wire [2:0] CSR_OP,
    input wire [4:0] CSR_UIMM,
    input wire [31:0] CSR_DATA_IN,
    output reg [31:0] CSR_DATA_OUT,
    
    // from pipeline stage 1
    input wire [31:0] PC_PLUS,
    
    // interface with CLIC
    input wire E_IRQ,
    input wire T_IRQ,
    input wire S_IRQ,
    
    // interface with Machine Control Module
    input wire I_OR_E,
    input wire SET_CAUSE,
    input wire [3:0] CAUSE_IN,
    input wire SET_EPC,
    input wire INSTRET_INC,
    input wire MIE_CLEAR,
    input wire MIE_SET,
    output reg MIE,
    output wire MEIE_OUT,
    output wire MTIE_OUT,
    output wire MSIE_OUT,
    output wire MEIP_OUT,
    output wire MTIP_OUT,
    output wire MSIP_OUT,
    
    // platform real time CLK value
    input wire [63:0] REAL_TIME,
    
    // these two outputs are connected to the PC MUX
    output wire [31:0] EPC_OUT,
    output wire [31:0] TRAP_ADDRESS

    );

    // Machine trap setup
    wire [31:0] mstatus; // machine status register
    wire [31:0] misa; // machine ISA register
    wire [31:0] mie_reg; // machine interrupt enable register
    wire [31:0] mtvec;
    wire [1:0] mxl; // machine XLEN
    wire [25:0] mextensions; // ISA extensions
    reg [1:0] mtvec_mode; // machine trap mode
    reg [29:0] mtvec_base; // machine trap base address
    reg mpie; // mach. prior interrupt enable
    reg meie; // mach. external interrupt enable
    reg mtie; // mach. timer interrupt enable
    reg msie; // mach. software interrupt enable

    // Machine trap handling
    reg [31:0] mscratch; // machine scratch register
    reg [31:0] mepc; // machine exception program counter
    reg [31:0] mtval; // machine trap value register
    wire [31:0] mcause; // machine trap cause register
    wire [31:0] mip_reg; // machine interrupt pending register
    reg int_or_exc; // interrupt or exception signal
    reg [3:0] cause; // interrupt cause
    reg meip; // mach. external interrupt pending
    reg mtip; // mach. timer interrupt pending
    reg msip; // mach. software interrupt pending

    // Machine counters
    reg [63:0] mcycle;
    reg [63:0] mtime;
    reg [63:0] minstret;

    // Machine counters setup
    wire [31:0] mcountinhibit;
    reg mcountinhibit_cy;
    reg mcountinhibit_ir;

    // CSR operation control
    // ----------------------------------------------------------------------------

    reg [31:0] data_wr;
    wire [31:0] pre_data;

    assign pre_data = CSR_OP[2] == 1'b1 ? {27'b0, CSR_UIMM} : CSR_DATA_IN;

    always @*
    begin
        case(CSR_OP[1:0])
            `CSR_RW: data_wr <= pre_data;
            `CSR_RS: data_wr <= CSR_DATA_OUT | pre_data;
            `CSR_RC: data_wr <= CSR_DATA_OUT & ~pre_data;
            `CSR_NOP: data_wr <= CSR_DATA_OUT;
        endcase
    end

    always @*
    begin
        case(CSR_ADDR)
            `CYCLE:         CSR_DATA_OUT = mcycle[31:0];
            `CYCLEH:        CSR_DATA_OUT = mcycle[63:32];
            `TIME:          CSR_DATA_OUT = mtime[31:0];
            `TIMEH:         CSR_DATA_OUT = mtime[63:32];
            `INSTRET:       CSR_DATA_OUT = minstret[31:0];
            `INSTRETH:      CSR_DATA_OUT = minstret[63:32];
            `MSTATUS:       CSR_DATA_OUT = mstatus;
            `MISA:          CSR_DATA_OUT = misa;
            `MIE:           CSR_DATA_OUT = mie_reg;
            `MTVEC:         CSR_DATA_OUT = mtvec;
            `MSCRATCH:      CSR_DATA_OUT = mscratch;
            `MEPC:          CSR_DATA_OUT = mepc;
            `MCAUSE:        CSR_DATA_OUT = mcause;
            `MTVAL:         CSR_DATA_OUT = 32'b0;
            `MIP:           CSR_DATA_OUT = mip_reg;
            `MCYCLE:        CSR_DATA_OUT = mcycle[31:0];
            `MCYCLEH:       CSR_DATA_OUT = mcycle[63:32];
            `MINSTRET:      CSR_DATA_OUT = minstret[31:0];
            `MINSTRETH:     CSR_DATA_OUT = minstret[63:32];
            `MCOUNTINHIBIT: CSR_DATA_OUT = mcountinhibit;
            default:        CSR_DATA_OUT = 32'b0;
        endcase
    end

    // MSTATUS register
    //                       MPP           
    assign mstatus = {19'b0, 2'b11, 3'b0, mpie, 3'b0 , MIE, 3'b0};
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            MIE <= 1'b0;
            mpie <= 1'b1;
        end
        else if(CSR_ADDR == `MSTATUS && WR_EN)
        begin
            MIE <= data_wr[3];
            mpie <= data_wr[7];
        end
        else if(MIE_CLEAR == 1'b1) MIE <= 1'b0;
        else if(MIE_SET == 1'b1)
        begin
            MIE <= mpie;
            mpie <= 1'b1;
        end
    end

    // MISA register
    assign mxl = 2'b01;
    assign mextensions = 26'b00000000000000000100000000;
    assign misa = {mxl, 4'b0, mextensions};

    // MIE register
    assign mie_reg = {20'b0, meie, 3'b0, mtie, 3'b0, msie, 3'b0};
    assign MEIE_OUT = meie;
    assign MTIE_OUT = mtie;
    assign MSIE_OUT = msie;
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            meie <= 1'b0;
            mtie <= 1'b0;
            msie <= 1'b0;
        end
        else if(CSR_ADDR == `MIE && WR_EN)
        begin            
            meie <= data_wr[11];
            mtie <= data_wr[7];
            msie <= data_wr[3];
        end
    end
    
    // MTVEC register
    assign mtvec = {mtvec_base, mtvec_mode};
    wire [31:0] trap_mux_out;
    wire [31:0] vec_mux_out;
    wire [31:0] base_offset;
    assign base_offset = cause << 2;
    assign trap_mux_out = int_or_exc ? vec_mux_out : {mtvec_base, 2'b00};
    assign vec_mux_out = mtvec[0] ? {mtvec_base, 2'b00} + base_offset : {mtvec_base, 2'b00};
    assign TRAP_ADDRESS = trap_mux_out;
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            mtvec_mode <= `MTVEC_MODE_RESET;
            mtvec_base <= `MTVEC_BASE_RESET;
        end
        else if(CSR_ADDR == `MTVEC && WR_EN)
        begin            
            mtvec_mode <= data_wr[1:0];
            mtvec_base <= data_wr[31:2];
        end
    end
    
    // MSCRATCH register
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET) mscratch <= `MSCRATCH_RESET;
        else if(CSR_ADDR == `MSCRATCH && WR_EN) mscratch <= data_wr;
    end
    
    // MEPC register
    assign EPC_OUT = mepc;
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET) mepc <= `MEPC_RESET;
        else if(SET_EPC) mepc <= PC_PLUS;
        else if(CSR_ADDR == `MEPC && WR_EN) mepc <= {data_wr[31:2], 2'b00};
    end

    // MCAUSE register
    assign mcause = {int_or_exc, 27'b0, cause};
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET) 
        begin
            cause <= 4'b0000;
            int_or_exc <= 1'b0;
        end
        else if(SET_CAUSE)
        begin
            cause <= CAUSE_IN;
            int_or_exc <= I_OR_E;
        end
    end
    
    // MIP register
    assign mip_reg = {20'b0, meip, 3'b0, mtip, 3'b0, msip, 3'b0};
    assign MEIP_OUT = meip;
    assign MTIP_OUT = mtip;
    assign MSIP_OUT = msip;
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            meip <= 1'b0;
            mtip <= 1'b0;
            msip <= 1'b0;
        end
        else
        begin
            meip <= E_IRQ;
            mtip <= T_IRQ;
            msip <= S_IRQ;
        end
    end    
    
    // MCOUNTINHIBIT register
    assign mcountinhibit = {29'b0, mcountinhibit_ir, 1'b0, mcountinhibit_cy};
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            mcountinhibit_cy <= `MCOUNTINHIBIT_CY_RESET;
            mcountinhibit_ir <= `MCOUNTINHIBIT_IR_RESET;
        end
        else if(CSR_ADDR == `MCOUNTINHIBIT && WR_EN)
        begin
            mcountinhibit_cy <= data_wr[2];
            mcountinhibit_ir <= data_wr[0]; 
        end
    end
    
    // Counters
    always @(posedge CLK or posedge RESET)
    begin
        if(RESET)
        begin
            mcycle <= {`MCYCLEH_RESET, `MCYCLE_RESET};
            minstret <= {`MINSTRETH_RESET, `MINSTRET_RESET};
            mtime <= {`MTIMEH_RESET, `MTIME_RESET};
        end
        else
        begin
            mtime <= REAL_TIME;
            if(CSR_ADDR == `MCYCLE && WR_EN)
            begin            
                mcycle[31:0] <= data_wr;
            end
            else if(CSR_ADDR == `MCYCLEH && WR_EN)
            begin            
                mcycle[63:32] <= data_wr;
            end
            else
            begin
                if(mcountinhibit_cy == 1'b0) mcycle <= mcycle + 1;
            end
            if(CSR_ADDR == `MINSTRET && WR_EN)
            begin
                minstret[31:0] <= data_wr;
            end
            else if(CSR_ADDR == `MINSTRETH && WR_EN)
            begin
                minstret[63:32] <= data_wr;
            end
            else
            begin
                if(mcountinhibit_ir == 1'b0) minstret <= minstret + INSTRET_INC;
            end
        end
    end 
    
endmodule