`ifndef PES
`define PES 2
`endif

// SIMD MIPS: Part 1 complete; Parts 2 and 3 pending.
// PE p uses [p*32 +: 32]. ID_* feed EX; EX_* feed MEM; MEM_* feed WB.
// EX results are combinational. ALUOp[4] selects a PE destination.
// Memory is 512 words; instruction and data addresses are byte addresses.

`define ALUAND 4'b0000
`define ALUOR  4'b0001
`define ALUADD 4'b0010
`define ALUSUB 4'b0110
`define ALUSLT 4'b0111
`define ALULUI 4'b1000
`define ALUXOR 4'b1111

// ================= PART 1 BEGIN: CU AND PIPELINE =================
module processor(output reg halt, input reset, clk);
    
    wire pe_ready;
    wire [`PES*32-1:0] pe_rs, pe_rt, pe_execute_result;
    wire [`PES-1:0] pe_live;
    wire [31:0] gor_execute_result;

    wire [4:0] pe_read_rs, pe_read_rt;
    wire [`PES*32-1:0] pe_arithmetic_result, pe_communication_result;
    reg ID_valid, ID_PE;
    reg [2:0] ID_special;
    reg [4:0] ID_ALUOp, ID_rd;
    reg [31:0] ID_s, ID_t, ID_src;
    reg [`PES*32-1:0] ID_ps, ID_pt, ID_p_src;
    reg [`PES-1:0] ID_mask;
    reg EX_valid, EX_PE;
    reg [2:0] EX_special;
    reg [`PES*32-1:0] EX_pr;
    reg [`PES-1:0] EX_mask;
    reg [4:0] EX_rd;
    reg MEM_valid, MEM_PE;
    reg [2:0] MEM_special;
    reg [`PES*32-1:0] MEM_pr;
    reg [`PES-1:0] MEM_mask;
    reg [4:0] MEM_rd;
    wire pe_commit, pe_control_commit;
    reg [31:0] m [0:511];
    reg [31:0] r [0:31];
    reg [31:0] IF_pc, IF_ir, IF_instruction_pc;
    reg IF_valid, stopping;
    reg ID_MemRead, ID_MemWrite, ID_Bad;
    reg EX_MemRead, EX_MemWrite, EX_Bad;
    reg MEM_Bad;
    reg [31:0] EX_alu, EX_t, MEM_v;

    // ================= PART 2 BEGIN: PE LOGIC =====================
    reg [31:0] PE_reg[0:31][0:`PES-1];
    wire [`PES*32-1:0] next_dl;
    reg [`PES*32-1:0] EX_dl, MEM_dl;

    // Part 2 is ready; Part 3 communication remains unfinished.
    assign pe_ready = 1'b1;

    genvar p;
    generate
        for (p=0; p<`PES; p=p+1) begin: PE_LOGIC
            // Raw reads for decode; Part 1 handles forwarding and capture.
            assign pe_rs[p*32 +: 32] = PE_reg[pe_read_rs][p];
            assign pe_rt[p*32 +: 32] = PE_reg[pe_read_rt][p];
            assign pe_live[p] = PE_reg[31][p][0];

            // Captured, forwarded operands for this PE's EX calculation.
            wire [31:0] a = ID_ps[p*32 +: 32];
            wire [31:0] b = ID_p_src[p*32 +: 32];
            wire [31:0] t = ID_pt[p*32 +: 32];
            reg [31:0] result, proposed_dl;

            assign pe_arithmetic_result[p*32 +: 32] = result;
            assign next_dl[p*32 +: 32] = proposed_dl;

            always @* begin
                case (ID_ALUOp[3:0])
                    `ALUAND: result = a & b;
                    `ALUOR:  result = a | b;
                    `ALUADD: result = a + b;
                    `ALUSUB: result = a - b;
                    `ALUSLT: result = {31'b0, (a < b)};
                    `ALULUI: result = b << 16;
                    `ALUXOR: result = a ^ b;
                    default: result = 0;
                endcase

                // Calculate a candidate; do not change actual PE state here.
                proposed_dl = PE_reg[28][p];
                case (ID_special)
                    1: proposed_dl = PE_reg[28][p]
                                     ? PE_reg[28][p] : (a == t); // offeq
                    2: proposed_dl = PE_reg[28][p] + |PE_reg[28][p]; // pushen
                    3: proposed_dl = PE_reg[28][p] - |PE_reg[28][p]; // popen
                    4: begin // gor -- implemented in Part 3
                    end
                    5: begin // bcast -- implemented in Part 3
                    end
                    6: begin // net -- implemented in Part 3
                    end
                    default: begin end
                endcase
            end
        end
    endgenerate

    integer regnum, pe;
    always @(posedge clk) begin
        if (reset) begin
            EX_dl <= 0;
            MEM_dl <= 0;
            for (regnum=0; regnum<32; regnum=regnum+1)
                for (pe=0; pe<`PES; pe=pe+1)
                    PE_reg[regnum][pe] <= 0;

            for (pe=0; pe<`PES; pe=pe+1) begin
                PE_reg[29][pe] <= pe;
                PE_reg[30][pe] <= `PES;
                PE_reg[31][pe] <= 1;
            end
        end else if (!halt) begin
            // Advance candidate enable updates alongside Part 1's pipeline.
            EX_dl <= next_dl;
            MEM_dl <= EX_dl;

            for (pe=0; pe<`PES; pe=pe+1) begin
                if (pe_commit && MEM_mask[pe] && MEM_rd>0 && MEM_rd<28)
                    PE_reg[MEM_rd][pe] <= MEM_pr[pe*32 +: 32];

                // Enable management also runs for disabled PEs.
                if (pe_control_commit) begin
                    PE_reg[28][pe] <= MEM_dl[pe*32 +: 32];
                    PE_reg[31][pe] <= (MEM_dl[pe*32 +: 32] == 0);
                end
            end
        end
    end
    // ================= PART 2 END: PE LOGIC =======================

    // ================= PART 3 BEGIN: COMMUNICATION ================
    // Add communication logic here; replace the placeholders.
    // The result selector below already connects Parts 2 and 3.
    assign gor_execute_result = 32'b0;       // TODO PART 3
    assign pe_communication_result = {(`PES*32){1'b0}}; // TODO PART 3
    // ================= PART 3 END: COMMUNICATION ==================

    // PART 1: one result selector
    assign pe_execute_result = (ID_special==5 || ID_special==6)
                             ? pe_communication_result : pe_arithmetic_result;

    // Decode controls distinguish source and destination register banks.
    // In particular gor reads PEs but writes CU; bcast does the reverse.
    reg d_simd, d_source_pe, d_pe, d_write, d_load, d_store;
    reg d_branch, d_immediate, d_needs, d_needt, d_bad;
    reg [3:0] d_alu;
    reg [2:0] d_special;
    reg [4:0] d_rd;
    reg [31:0] imm;
    reg [5:0] baseop;
    wire [5:0] op = IF_ir[31:26];
    wire [5:0] funct = IF_ir[5:0];
    wire [4:0] rs = IF_ir[25:21];
    wire [4:0] rt = IF_ir[20:16];
    assign pe_read_rs=rs;
    assign pe_read_rt=rt;

    // Special codes: 0 normal, 1 offeq, 2 pushen, 3 popen,
    // 4 gor, 5 bcast, 6 net. This block only decodes them.
    always @* begin
        d_simd=0; d_source_pe=0; d_pe=0; d_write=0;
        d_load=0; d_store=0; d_branch=0; d_immediate=0;
        d_needs=0; d_needt=0; d_bad=0;
        d_alu=`ALUOR; d_special=0; d_rd=0;
        imm={{16{IF_ir[15]}},IF_ir[15:0]};
        baseop=op;
        if (op==0 || op==16) begin
            d_simd=(op==16); d_source_pe=d_simd; d_pe=d_simd;
            d_write=1; d_needs=1; d_needt=1; d_rd=IF_ir[15:11];
            case (funct)
                33: d_alu=`ALUADD;
                35: d_alu=`ALUSUB;
                36: d_alu=`ALUAND;
                37: d_alu=`ALUOR;
                38: d_alu=`ALUXOR;
                43: d_alu=`ALUSLT;
                0: if (d_simd) begin d_special=1; d_write=0; end else d_bad=1;
                4: if (d_simd) begin
                    d_special=2; d_write=0; d_needs=0; d_needt=0;
                end else d_bad=1;
                5: if (d_simd) begin
                    d_special=3; d_write=0; d_needs=0; d_needt=0;
                end else d_bad=1;
                1: if (d_simd) begin
                    d_special=4; d_pe=0; d_rd=rt; d_needt=0;
                end else d_bad=1;
                2: if (d_simd) begin
                    d_special=5; d_source_pe=0; d_rd=rt; d_needt=0;
                end else d_bad=1;
                34: if (d_simd) d_special=6; else d_bad=1;
                default: d_bad=1;
            endcase
        end else begin
            case (op)
                25,27,28,29,30,31: begin
                    d_simd=1; d_source_pe=1; d_pe=1; baseop=op-6'd16;
                end
                default: begin end
            endcase
            d_write=1; d_needs=1; d_immediate=1; d_rd=rt;
            case (baseop)
                9: d_alu=`ALUADD;
                11: d_alu=`ALUSLT;
                12: begin d_alu=`ALUAND; imm={16'b0,IF_ir[15:0]}; end
                13: begin d_alu=`ALUOR; imm={16'b0,IF_ir[15:0]}; end
                14: begin d_alu=`ALUXOR; imm={16'b0,IF_ir[15:0]}; end
                15: begin d_alu=`ALULUI; d_needs=0; end
                4: begin d_branch=1; d_write=0; d_needt=1; end
                35: begin d_load=1; d_alu=`ALUADD; end
                43: begin d_store=1; d_write=0; d_needt=1; d_alu=`ALUADD; end
                default: d_bad=1;
            endcase
        end
        if (d_bad) begin
            d_write=0; d_load=0; d_store=0; d_branch=0;
            d_needs=0; d_needt=0; d_special=0;
        end
        // PE $0 and $28-$31 cannot be ordinary destinations.
        if (!d_write || (d_pe && d_rd>=28)) d_rd=0;
    end

    wire running=!halt && !reset;
    wire ex_s=ID_valid && ID_rd!=0 && rs==ID_rd && d_source_pe==ID_PE;
    wire ex_t=ID_valid && ID_rd!=0 && rt==ID_rd && d_source_pe==ID_PE;
    wire mem_s=EX_valid && EX_rd!=0 && rs==EX_rd && d_source_pe==EX_PE;
    wire mem_t=EX_valid && EX_rd!=0 && rt==EX_rd && d_source_pe==EX_PE;
    wire wb_s=MEM_valid && MEM_rd!=0 && rs==MEM_rd && d_source_pe==MEM_PE;
    wire wb_t=MEM_valid && MEM_rd!=0 && rt==MEM_rd && d_source_pe==MEM_PE;
    wire load_use=ID_MemRead && ((d_needs && ex_s) || (d_needt && ex_t));

    // Conservative interlock for enable state: let it retire before a later
    // SIMD instruction samples pe_live or the special PE registers.
    wire enable_pending=(ID_valid && ID_special>=1 && ID_special<=3) ||
                        (EX_valid && EX_special>=1 && EX_special<=3) ||
                        (MEM_valid && MEM_special>=1 && MEM_special<=3);
    // Illegal instructions must reach the stop path even when PEs are unready.
    wire blocked=IF_valid && (load_use ||
                 (d_simd && !d_bad && (!pe_ready || enable_pending)));

    reg [31:0] alu;
    wire [31:0] v=EX_MemRead ? m[EX_alu>>2] : EX_alu;
    reg [31:0] s,t;
    wire [`PES*32-1:0] ps,pt;
    // Youngest matching CU producer wins.
    always @* begin
        s=(rs==0) ? 0 : r[rs];
        t=(rt==0) ? 0 : r[rt];
        if (!d_source_pe && rs!=0) begin
            if (ex_s && !ID_MemRead) s=alu;
            else if (mem_s) s=v;
            else if (wb_s) s=MEM_v;
        end
        if (!d_source_pe && rt!=0) begin
            if (ex_t && !ID_MemRead) t=alu;
            else if (mem_t) t=v;
            else if (wb_t) t=MEM_v;
        end
    end

    // One forwarding pair per PE. A masked producer is skipped per lane,
    // allowing an older enabled result (or the register file) to supply data.
    genvar lane;
    generate for (lane=0;lane<`PES;lane=lane+1) begin: PE_FORWARD
        assign ps[lane*32 +: 32]=(rs==0) ? 32'b0 :
            (d_source_pe && ex_s && ID_mask[lane]) ? pe_execute_result[lane*32 +: 32] :
            (d_source_pe && mem_s && EX_mask[lane]) ? EX_pr[lane*32 +: 32] :
            (d_source_pe && wb_s && MEM_mask[lane]) ? MEM_pr[lane*32 +: 32] :
            pe_rs[lane*32 +: 32];
        assign pt[lane*32 +: 32]=(rt==0) ? 32'b0 :
            (d_source_pe && ex_t && ID_mask[lane]) ? pe_execute_result[lane*32 +: 32] :
            (d_source_pe && mem_t && EX_mask[lane]) ? EX_pr[lane*32 +: 32] :
            (d_source_pe && wb_t && MEM_mask[lane]) ? MEM_pr[lane*32 +: 32] :
            pe_rt[lane*32 +: 32];
`ifdef TRACE
        always @(posedge clk) if (pe_commit && MEM_mask[lane])
            $display("WB PE%0d r%0d=%h",lane,MEM_rd,MEM_pr[lane*32 +: 32]);
`endif
    end endgenerate

    // CU arithmetic only. Teammate sections provide internal PE and gor EX results.
    always @* begin
        case (ID_ALUOp[3:0])
            `ALUAND: alu=ID_s & ID_src;
            `ALUOR: alu=ID_s | ID_src;
            `ALUADD: alu=ID_s + ID_src;
            `ALUSUB: alu=ID_s - ID_src;
            `ALUSLT: alu={31'b0,ID_s<ID_src};
            `ALUXOR: alu=ID_s ^ ID_src;
            default: alu=ID_src<<16;
        endcase
        if (ID_special==4) alu=gor_execute_result;
    end

    wire taken=IF_valid && !blocked && d_branch && s==t;
    wire [31:0] target=IF_instruction_pc+4+(imm<<2);
    assign pe_commit=running && MEM_valid && MEM_PE && MEM_rd!=0;
    assign pe_control_commit=running && MEM_valid && MEM_special>=1 && MEM_special<=3;

    // Five stage pipeline. Combinational result logic
    // above avoids ordering dependencies between separate posedge blocks.
    integer k;
    always @(posedge clk) begin
        if (reset) begin
            halt<=0; stopping<=0; IF_pc<=0; IF_ir<=32'h00000025;
            IF_instruction_pc<=0; IF_valid<=0;
            for (k=0;k<32;k=k+1) r[k]<=0;
            ID_valid<=0; ID_PE<=0; ID_special<=0; ID_ALUOp<=0;
            ID_s<=0; ID_t<=0; ID_src<=0; ID_ps<=0; ID_pt<=0;
            ID_p_src<=0; ID_mask<=0; ID_rd<=0;
            ID_MemRead<=0; ID_MemWrite<=0; ID_Bad<=0;
            EX_valid<=0; EX_PE<=0; EX_special<=0; EX_pr<=0;
            EX_mask<=0; EX_rd<=0; EX_alu<=0; EX_t<=0;
            EX_MemRead<=0; EX_MemWrite<=0; EX_Bad<=0;
            MEM_valid<=0; MEM_PE<=0; MEM_special<=0; MEM_pr<=0;
            MEM_mask<=0; MEM_rd<=0; MEM_v<=0; MEM_Bad<=0;
        end else if (!halt) begin
            // WB: ordinary CU writes only. PE writes belong to teammates.
            if (MEM_valid) begin
                if (!MEM_PE && MEM_rd!=0) r[MEM_rd]<=MEM_v;
                if (MEM_Bad) halt<=1;
            end
            // No younger side effects when the illegal instruction retires.
            if (!(MEM_valid && MEM_Bad)) begin
                // MEM
                if (EX_valid && EX_MemWrite) m[EX_alu>>2]<=EX_t;
                MEM_valid<=EX_valid; MEM_PE<=EX_PE; MEM_special<=EX_special;
                MEM_pr<=EX_pr; MEM_mask<=EX_mask; MEM_rd<=EX_rd;
                MEM_v<=v; MEM_Bad<=EX_Bad;
                // EX
                EX_valid<=ID_valid; EX_PE<=ID_PE; EX_special<=ID_special;
                EX_pr<=pe_execute_result; EX_mask<=ID_mask; EX_rd<=ID_rd;
                EX_alu<=alu; EX_t<=ID_t; EX_MemRead<=ID_MemRead;
                EX_MemWrite<=ID_MemWrite; EX_Bad<=ID_Bad;
                // ID: a stall holds IF and inserts a bubble into EX.
                ID_valid<=IF_valid && !blocked;
                ID_rd<=0; ID_MemRead<=0; ID_MemWrite<=0;
                ID_Bad<=0; ID_special<=0;
                if (IF_valid && !blocked) begin
                    ID_PE<=d_pe; ID_special<=d_special;
                    ID_ALUOp<={d_pe,d_alu}; ID_rd<=d_rd;
                    ID_s<=s; ID_t<=t; ID_src<=d_immediate ? imm : t;
                    ID_ps<=ps; ID_pt<=pt;
                    ID_p_src<=d_immediate ? {`PES{imm}} : pt;
                    ID_mask<=pe_live;
                    ID_MemRead<=d_load; ID_MemWrite<=d_store; ID_Bad<=d_bad;
                end
                // IF: branch target is relative to the decoded instruction.
                // A taken branch discards the sequential fetch (no delay slot).
                if (!blocked) begin
                    if (stopping || (IF_valid && d_bad)) begin
                        IF_valid<=0; stopping<=1;
                    end else if (taken) begin
                        IF_pc<=target; IF_valid<=0;
                    end else begin
                        IF_ir<=m[IF_pc>>2]; IF_instruction_pc<=IF_pc;
                        IF_pc<=IF_pc+4; IF_valid<=1;
                    end
                end
            end
        end
    end

`ifdef TRACE
    always @(posedge clk) if (running) begin
        $display("IF pc=%h ir=%h valid=%b blocked=%b",IF_instruction_pc,IF_ir,IF_valid,blocked);
        if (MEM_valid)
            $display("WB PE=%b rd=%0d CU=%h special=%0d bad=%b",MEM_PE,MEM_rd,MEM_v,MEM_special,MEM_Bad);
    end
`endif
endmodule
// ================= PART 1 END: CU AND PIPELINE ===================

// ================= PART 3 BEGIN: TEAM TEST PROGRAM ================
// Add the team testbench here after Parts 2 and 3 are ready.
// ================= PART 3 END: TEAM TEST PROGRAM ==================
