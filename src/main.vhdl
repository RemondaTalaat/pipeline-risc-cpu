library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;

entity main is
    port (
        clk, rst, interrupt : in std_logic;
        in_value            : in std_logic_vector(31 downto 0);
        out_value           : out std_logic_vector(31 downto 0);
        hlt                 : out std_logic;

        -- testing signals

        -- '1' if testbench is taking control now of the memory and regs
        tb_controls         : in std_logic;

        -- to reg_file
        tb_rf_src0_adr      : in std_logic_vector(3 downto 0);
        tb_rf_dst0_adr      : in std_logic_vector(3 downto 0);
        tb_rf_dst0_value    : in std_logic_vector(31 downto 0);
        -- from reg_file
        rf_tb_dst0_value    : out std_logic_vector(31 downto 0);

        -- to instr_mem
        tb_im_rd            : in std_logic;
        tb_im_wr            : in std_logic;
        tb_im_data_in       : in std_logic_vector(15 downto 0);
        tb_im_adr           : in std_logic_vector(31 downto 0);
        -- from instr_mem
        tb_im_data_out      : out std_logic_vector(15 downto 0);

        -- to data_mem
        tb_dm_rd            : in std_logic;
        tb_dm_wr            : in std_logic;
        tb_dm_data_in       : in std_logic_vector(31 downto 0);
        tb_dm_adr           : in std_logic_vector(31 downto 0);
        -- from data_mem
        tb_dm_data_out      : out std_logic_vector(31 downto 0);

        tb_ccr_in           : in std_logic_vector(2 downto 0);
        tb_ccr_out          : out std_logic_vector(2 downto 0)
    );
end entity;

architecture rtl of main is
    -- ccr and its inputs
    signal ccr                           : std_logic_vector(2 downto 0);
    signal xs_ccr                        : std_logic_vector(ccr'range);
    signal ms_ccr                        : std_logic_vector(ccr'range);
    signal ms_ccr_sel                    : std_logic;

    -- hdu --> fetch_stage,f_d_buffer,d_x_buffer
    signal hdu_stall                     : std_logic;

    -- hdu --> execute_stage
    signal hdu_xs_op_1_sel               : std_logic_vector(1 downto 0);
    signal hdu_xs_op_2_sel               : std_logic_vector(1 downto 0);

    --> fetch_stage
    signal fsi_if_flush                  : std_logic;
    signal fsi_parallel_load_pc_selector : std_logic;
    signal fsi_loaded_pc_value           : std_logic_vector(31 downto 0);
    signal fsi_branch_address            : std_logic_vector(31 downto 0);
    signal fsi_hashed_address            : std_logic_vector(3 downto 0);

    -- fetch_stage --> f_d_buffer
    signal fs_fdb_interrupt              : std_logic;
    signal fs_fdb_instruction_bits       : std_logic_vector(31 downto 0);
    signal fs_fdb_predicted_address      : std_logic_vector(31 downto 0);
    signal fs_fdb_hashed_address         : std_logic_vector(3 downto 0);
    signal fs_fdb_inc_pc                 : std_logic_vector(31 downto 0);

    -- f_d_buffer --> decode_stage
    signal fdb_ds_instr                  : std_logic_vector(31 downto 0);
    signal fdb_ds_inc_pc                 : std_logic_vector(31 downto 0);
    signal fdb_ds_interrupt              : std_logic;

    -- decode_stage --> d_x_buffer
    signal ds_dxb_alu_op                 : std_logic_vector (3 downto 0);
    signal ds_dxb_operand0               : std_logic_vector(32 - 1 downto 0); -- TODO: where its input?
    signal ds_dxb_operand1               : std_logic_vector(32 - 1 downto 0); -- TODO: where its input?
    signal ds_dxb_dest_0                 : std_logic_vector(4 - 1 downto 0);
    signal ds_dxb_dest_1                 : std_logic_vector(4 - 1 downto 0);
    signal ds_dxb_opcode                 : std_logic_vector(7 - 1 downto 0);
    signal ds_dxb_r_w                    : std_logic_vector(1 downto 0);
    signal ds_dxb_interrupt              : std_logic;
    signal ds_dxb_src2_value             : std_logic_vector(32 - 1 downto 0);
    signal ds_dxb_src2_sel               : std_logic;

    -- decode_stage --> reg_file
    signal ds_rf_src0_adr                : std_logic_vector(3 downto 0);
    signal ds_rf_src1_adr                : std_logic_vector(3 downto 0);
    signal ds_rf_br_io_enbl              : std_logic_vector(1 downto 0);
    signal ds_rf_rst                     : std_logic;

    -- reg_file --> decode_stage
    signal rf_dxb_op0_value              : std_logic_vector(31 downto 0);
    signal rf_dxb_op1_value              : std_logic_vector(31 downto 0);

    -- d_x_buffer --> execute_stage
    signal dxb_xs_alu_op                 : std_logic_vector (3 downto 0);
    signal dxb_xs_operand0               : std_logic_vector(32 - 1 downto 0);
    signal dxb_xs_operand1               : std_logic_vector(32 - 1 downto 0);
    signal dxb_xs_dest_0                 : std_logic_vector(4 - 1 downto 0);
    signal dxb_xs_dest_1                 : std_logic_vector(4 - 1 downto 0);
    signal dxb_xs_opcode                 : std_logic_vector(7 - 1 downto 0);
    signal dxb_xs_r_w                    : std_logic_vector(1 downto 0);
    signal dxb_xs_interrupt              : std_logic;

    --> reg_file
    signal rf_dst0_adr                   : std_logic_vector(3 downto 0);
    signal rf_dst1_adr                   : std_logic_vector(3 downto 0);
    signal rf_src0_adr                   : std_logic_vector(3 downto 0);
    signal rf_src1_adr                   : std_logic_vector(3 downto 0);
    signal rf_wb0_value                  : std_logic_vector(31 downto 0);
    signal rf_br_io_enbl                 : std_logic_vector(1 downto 0);
    signal rf_rst                        : std_logic;

    -- x_m_buffer --> execute_stage
    signal xmb_xs_aluout                 : std_logic_vector(31 downto 0);

    -- execute_stage --> x_m_buffer
    signal xs_xmb_alu_output             : std_logic_vector(31 downto 0);
    signal xs_xmb_interpt                : std_logic;
    signal xs_xmb_destination_0          : std_logic_vector(4 - 1 downto 0);
    signal xs_xmb_destination_1          : std_logic_vector(4 - 1 downto 0);
    signal xs_xmb_dest_value_0           : std_logic_vector(32 - 1 downto 0);
    signal xs_xmb_dest_value_1           : std_logic_vector(32 - 1 downto 0);
    signal xs_xmb_mem_adr                : std_logic_vector(31 downto 0);
    signal xs_xmb_mem_input              : std_logic_vector(31 downto 0);
    signal xs_xmb_opcode                 : std_logic_vector(6 downto 0);
    signal xs_xmb_r_w                    : std_logic_vector(1 downto 0);

    -- memory_stage --> execute_stage,decode_stage
    signal ms_stalling_enable            : std_logic;

    -- memory_stage --> reg_file
    signal ms_rf_mwb_dest_1_value_out    : std_logic_vector(31 downto 0);
    signal ms_rf_mwb_dest_2_value_out    : std_logic_vector(31 downto 0);
    signal ms_rf_dst_reg_1_out           : std_logic_vector(3 downto 0);
    signal ms_rf_dst_reg_2_out           : std_logic_vector(3 downto 0);

    -- execute_stage --> memory_stage
    signal xmb_ms_xs_aluout              : std_logic_vector(32 - 1 downto 0);
    signal xmb_ms_mem_adr                : std_logic_vector(32 - 1 downto 0);
    signal xmb_ms_mem_input              : std_logic_vector(32 - 1 downto 0);
    signal xmb_ms_opcode                 : std_logic_vector(7 - 1 downto 0);
    signal xmb_ms_destination_0          : std_logic_vector(4 - 1 downto 0);
    signal xmb_ms_destination_1          : std_logic_vector(4 - 1 downto 0);
    signal xmb_ms_dest_value_0           : std_logic_vector(32 - 1 downto 0);
    signal xmb_ms_dest_value_1           : std_logic_vector(32 - 1 downto 0);
    signal xmb_ms_r_w                    : std_logic_vector(2 - 1 downto 0);
    signal xmb_ms_mwb_interrupt              : std_logic;

    -- m_w_buffer --> execute_stage
    signal mwb_xs_out_mem                : std_logic_vector(32 - 1 downto 0);

    -- memory_stage --> m_w_buffer
    signal ms_mwb_aluout                 : std_logic_vector(32 - 1 downto 0);
    signal ms_mwb_mem_input              : std_logic_vector(32 - 1 downto 0);
    signal ms_mwb_opcode                 : std_logic_vector(7 - 1 downto 0);
    signal ms_mwb_dest_0_adr             : std_logic_vector(4 - 1 downto 0);
    signal ms_mwb_dest_1_adr             : std_logic_vector(4 - 1 downto 0);
begin
    fetch_stage : entity work.fetch_stage
        port map(
            --IN
            clk                          => clk,
            rst                          => rst,
            in_interrupt                 => interrupt,

            in_stall                     => hdu_stall,                     --> hdu.Stall_signal
            in_if_flush                  => fsi_if_flush,                  --> TODO.TODO
            in_parallel_load_pc_selector => fsi_parallel_load_pc_selector, --> TODO.TODO
            in_loaded_pc_value           => fsi_loaded_pc_value,           --> TODO.TODO
            in_branch_address            => fsi_branch_address,            --> TODO.TODO
            in_hashed_address            => fsi_hashed_address,            --> TODO.TODO
            --OUT
            out_interrupt                => fs_fdb_interrupt,
            out_instruction_bits         => fs_fdb_instruction_bits,  --> f_d_buffer.in_instr
            out_predicted_address        => fs_fdb_predicted_address, --> TODO.TODO
            out_hashed_address           => fs_fdb_hashed_address,    --> TODO.TODO
            out_inc_pc                   => fs_fdb_inc_pc,            --> f_d_buffer.in_inc_pc

            -- testing
            tb_controls                  => tb_controls,              --> tb
            tb_mem_rd                    => tb_im_rd,                 --> tb
            tb_mem_wr                    => tb_im_wr,                 --> tb
            tb_mem_data_in               => tb_im_data_in,            --> tb
            tb_mem_adr                   => tb_im_adr,                --> tb
            tb_mem_data_out              => tb_im_data_out            --> tb
        );

    f_d_buffer : entity work.f_d_buffer
        port map(
            --IN
            clk           => clk,

            in_flush      => fsi_if_flush,            --> TODO.TODO
            in_instr      => fs_fdb_instruction_bits, --> fetch_stage.out_instruction_bits
            in_inc_pc     => fs_fdb_inc_pc,           --> fetch_stage.out_inc_pc
            in_interrupt  => fs_fdb_interrupt,        --> fetch_stage.out_interrupt
            --OUT
            out_instr     => fdb_ds_instr,            --> decode_stage.fdb_instr
            out_inc_pc    => fdb_ds_inc_pc,           --> decode_stage.fdb_inc_pc
            out_interrupt => fdb_ds_interrupt         --> decode_stage.fdb_interrupt
        );

    decode_stage : entity work.decode_stage
        port map(
            --IN
            in_zero_flag        => ccr(CCR_ZERO),      --> main

            fdb_instr           => fdb_ds_instr,       --> f_d_buffer.out_instr
            fdb_inc_pc          => fdb_ds_inc_pc,      --> f_d_buffer.out_inc_pc
            fdb_interrupt       => fdb_ds_interrupt,   --> f_d_buffer.out_interrupt
            mem_stalling_bit    => ms_stalling_enable, --> memory_stage.stalling_enable
            in_port             => in_value,           --> main
            --OUT
            dxb_alu_op          => ds_dxb_alu_op,      --> d_x_buffer.in_alu_op
            src2_value          => ds_dxb_src2_value,  --> d_x_buffer.in_src2_value
            src2_value_selector => ds_dxb_src2_sel,    --> d_x_buffer.in_sel_src2
            dxb_dest_0          => ds_dxb_dest_0,      --> d_x_buffer.in_dest_0
            dxb_dest_1          => ds_dxb_dest_1,      --> d_x_buffer.in_dest_1
            dxb_opcode          => ds_dxb_opcode,      --> d_x_buffer.in_opcode
            dxb_r_w             => ds_dxb_r_w,         --> d_x_buffer.in_r_w
            dxb_interrupt       => ds_dxb_interrupt,   --> d_x_buffer.in_interrupt

            rf_src0_adr         => ds_rf_src0_adr,     --> main
            rf_src1_adr         => ds_rf_src1_adr,     --> main
            hlt                 => hlt
        );

    reg_file : entity work.reg_file
        port map(
            --IN
            clk        => clk,

            rst        => rf_rst,                     --> main
            dst0_adr   => rf_dst0_adr,                --> main
            dst1_adr   => rf_dst1_adr,                --> main
            src0_adr   => rf_src0_adr,                --> main
            src1_adr   => rf_src1_adr,                --> main
            -- fetch_adr   => TODO, --> TODO.TODO

            wb0_value  => rf_wb0_value,               --> main
            wb1_value  => ms_rf_mwb_dest_2_value_out, --> memory_stage.destination_2_value_out

            in_value   => in_value,                   --> main

            br_io_enbl => rf_br_io_enbl,              --> main
            --OUT
            op0_value  => rf_dxb_op0_value,           --> d_x_buffer.in_operand0, tb
            op1_value  => rf_dxb_op1_value,           --> d_x_buffer.in_operand1

            -- fetch_value => TODO, --> TODO.TODO
            -- instr_adr   => TODO, --> TODO.TODO

            out_value  => out_value                   --> main
        );

    -- mux between (reg_file and tb) signals
    --IN
    rf_rst           <= rst or ds_rf_rst;
    rf_dst0_adr      <= tb_rf_dst0_adr when tb_controls = '1' else ms_rf_dst_reg_1_out;  --> memory_stage.destination_register_1_out
    rf_dst1_adr      <= (others => '1') when tb_controls = '1' else ms_rf_dst_reg_2_out; --> memory_stage.destination_register_2_out
    rf_src0_adr      <= tb_rf_src0_adr when tb_controls = '1' else ds_rf_src0_adr;
    rf_src1_adr      <= (others => '1') when tb_controls = '1' else ds_rf_src1_adr;
    rf_wb0_value     <= tb_rf_dst0_value when tb_controls = '1' else ms_rf_mwb_dest_1_value_out; --> memory_stage.destination_1_value_out
    rf_br_io_enbl    <= "00" when tb_controls = '1' else ds_rf_br_io_enbl;
    --OUT
    rf_tb_dst0_value <= rf_dxb_op0_value;

    d_x_buffer : entity work.d_x_buffer
        port map(
            --IN
            clk           => clk,

            in_stall      => hdu_stall,         --> hdu.Stall_signal
            in_operand0   => rf_dxb_op0_value,  --> reg_file.op0_value
            in_operand1   => rf_dxb_op1_value,  --> reg_file.op1_value
            in_alu_op     => ds_dxb_alu_op,     --> decode_stage.dxb_alu_op
            in_src2_value => ds_dxb_src2_value, --> decode_stage.src2_value
            in_sel_src2   => ds_dxb_src2_sel,   --> decode_stage.src2_value_selector
            in_dest_0     => ds_dxb_dest_0,     --> decode_stage.dxb_dest_0
            in_dest_1     => ds_dxb_dest_1,     --> decode_stage.dxb_dest_1
            in_opcode     => ds_dxb_opcode,     --> decode_stage.dxb_opcode
            in_r_w        => ds_dxb_r_w,        --> decode_stage.dxb_r_w
            in_interrupt  => ds_dxb_interrupt,  --> decode_stage.dxb_interrupt
            -- OUT
            out_alu_op    => dxb_xs_alu_op,     --> execute_stage.alu_operation
            out_operand0  => dxb_xs_operand0,   --> execute_stage.operand_1
            out_operand1  => dxb_xs_operand1,   --> execute_stage.operand_2
            out_dest_0    => dxb_xs_dest_0,     --> execute_stage.destination_register_1_in
            out_dest_1    => dxb_xs_dest_1,     --> execute_stage.destination_register_2_in
            out_opcode    => dxb_xs_opcode,     --> execute_stage.opCode_in
            out_interrupt => dxb_xs_interrupt   --> execute_stage.int_bit_in
            out_r_w       => dxb_xs_r_w         --> execute_stage.r_w_control_in
        );

    execute_stage : entity work.execute_stage
        port map(
            --IN
            clk                        => clk,

            alu_operation              => dxb_xs_alu_op,        --> d_x_buffer.out_alu_op
            operand_1                  => dxb_xs_operand0,      --> d_x_buffer.out_operand0
            operand_2                  => dxb_xs_operand1,      --> d_x_buffer.out_operand1
            destination_register_1_in  => dxb_xs_dest_0,        --> d_x_buffer.out_dest_0
            destination_register_2_in  => dxb_xs_dest_1,        --> d_x_buffer.dxb_xs_dest_1
            opCode_in                  => dxb_xs_opcode,        --> d_x_buffer.dxb_xs_opcode
            int_bit_in                 => dxb_xs_interrupt,     --> d_x_buffer.dxb_xs_interrupt
            r_w_control_in             => dxb_xs_r_w,           --> d_x_buffer.out_r_w

            mem_stalling_bit           => ms_stalling_enable,   --> memory_stage.stalling_enable
            alu_op_1_selector          => hdu_xs_op_1_sel,      --> hdu.operand_1_select
            alu_op_2_selector          => hdu_xs_op_2_sel,      --> hdu.operand_2_select
            forwarded_data_1           => xmb_ms_xs_aluout,     --> x_m_buffer.out_aluout
            forwarded_data_2           => mwb_xs_out_mem,       --> m_w_buffer.out_mem
            --OUT
            ccr_out                    => xs_ccr,               --> main
            alu_output                 => xs_xmb_alu_output,    --> x_m_buffer.in_aluout
            memory_address             => xs_xmb_mem_adr,       --> x_m_buffer.in_mem_adr
            memory_input               => xs_xmb_mem_input,     --> x_m_buffer.in_mem_inp
            opCode_out                 => xs_xmb_opcode,        --> x_m_buffer.in_opcode
            destination_register_1_out => xs_xmb_destination_0, --> x_m_buffer.in_destination_0
            destination_register_2_out => xs_xmb_destination_1, --> x_m_buffer.in_destination_1
            destination_1_value_out    => xs_xmb_dest_value_0,  --> x_m_buffer.in_dest_value_0
            destination_2_value_out    => xs_xmb_dest_value_1,  --> x_m_buffer.in_dest_value_1
            interrupt_bit_out          => xs_xmb_interpt        --> x_m_buffer.in_interrupt
            r_w_control_out            => xs_xmb_r_w            --> x_m_buffer.in_r_w
        );

    hdu : entity work.hdu
        port map(
            --IN
            -- opcode_decode    => TODO, --> TODO.TODO
            -- opcode_execute   => TODO, --> TODO.TODO
            -- opcode_memory    => TODO, --> TODO.TODO
            -- decode_src_reg_1 => TODO, --> TODO.TODO
            -- decode_src_reg_2 => TODO, --> TODO.TODO
            -- exe_dst_reg      => TODO, --> TODO.TODO
            -- mem_dst_reg      => TODO, --> TODO.TODO
            --OUT
            operand_1_select => hdu_xs_op_1_sel, --> execute_stage.alu_op_1_selector
            operand_2_select => hdu_xs_op_2_sel, --> execute_stage.alu_op_1_selector
            Stall_signal     => hdu_stall        --> fetch_stage,f_d_buffer,d_x_buffer
        );

    x_m_buffer : entity work.x_m_buffer
        port map(
            --IN
            clk               => clk,

            in_aluout         => xs_xmb_alu_output,    --> execute_stage.alu_output
            in_mem_adr        => xs_xmb_mem_adr,       --> execute_stage.memory_address
            in_mem_inp        => xs_xmb_mem_input,     --> execute_stage.memory_input
            in_opcode         => xs_xmb_opcode,        --> execute_stage.opCode_out
            in_destination_0  => xs_xmb_destination_0, --> execute_stage.destination_register_1_out
            in_destination_1  => xs_xmb_destination_1, --> execute_stage.destination_register_2_out
            in_dest_value_0   => xs_xmb_dest_value_0,  --> execute_stage.destination_1_value_out
            in_dest_value_1   => xs_xmb_dest_value_1,  --> execute_stage.destination_2_value_out
            in_interrupt      => xs_xmb_interpt,       --> execute_stage.interrupt_bit_out
            in_r_w            => xs_xmb_r_w,           --> execute_stage.r_w_control_out
            --OUT
            out_aluout        => xmb_ms_xs_aluout,     --> memory_stage.alu_result
            out_mem_adr       => xmb_ms_mem_adr,       --> memory_stage.memory_address
            out_mem_inp       => xmb_ms_mem_input,     --> memory_stage.memory_in
            out_opcode        => xmb_ms_opcode,        --> memory_stage.opCode_in
            out_destination_0 => xmb_ms_destination_0, --> memory_stage.destination_register_1_in
            out_destination_1 => xmb_ms_destination_1, --> memory_stage.destination_register_2_in
            out_dest_value_0  => xmb_ms_dest_value_0,  --> memory_stage.destination_1_value
            out_dest_value_1  => xmb_ms_dest_value_1,  --> memory_stage.destination_2_value
            out_r_w           => xmb_ms_r_w,           --> memory_stage.r_w_control
            out_interrupt     => xmb_ms_mwb_interrupt      --> memory_stage.int_bit_in, m_w_buffer.in_interrupt
        );

    memory_stage : entity work.memory_stage
        port map(
            --IN
            clk                        => clk,

            ccr_in                     => ccr,                        --> main
            memory_address             => xmb_ms_mem_adr,             --> x_m_buffer.out_mem_adr
            memory_in                  => xmb_ms_mem_input,           --> x_m_buffer.out_mem_inp
            r_w_control                => xmb_ms_r_w,                 --> x_m_buffer.out_r_w
            alu_result                 => xmb_ms_xs_aluout,           --> x_m_buffer.out_aluout
            destination_register_1_in  => xmb_ms_destination_0,       --> x_m_buffer.out_destination_0
            destination_register_2_in  => xmb_ms_destination_1,       --> x_m_buffer.out_destination_1
            destination_1_value        => xmb_ms_dest_value_0,        --> x_m_buffer.out_dest_value_0
            destination_2_value        => xmb_ms_dest_value_1,        --> x_m_buffer.out_dest_value_1
            opCode_in                  => xmb_ms_opcode,              --> x_m_buffer.out_opcode
            int_bit_in                 => xmb_ms_mwb_interrupt,           --> x_m_buffer.out_interrupt
            --OUT
            alu_output                 => ms_mwb_aluout,              --> m_w_buffer.in_aluout
            memory_out                 => ms_mwb_mem_input,           --> m_w_buffer.in_mem
            opCode_out                 => ms_mwb_opcode,              --> m_w_buffer.in_opcode
            destination_register_1_out => ms_mwb_dest_0_adr,          --> m_w_buffer.in_destination_0
            destination_register_2_out => ms_mwb_dest_1_adr,          --> m_w_buffer.in_destination_1
            destination_1_value_out    => ms_rf_mwb_dest_1_value_out, --> reg_file.wb0_value
            destination_2_value_out    => ms_rf_mwb_dest_2_value_out, --> reg_file.wb1_value
            ccr_out                    => ms_ccr,                     --> main
            -- pc_selector                => TODO,                   --> TODO.TODO
            stalling_enable            => ms_stalling_enable,         --> execute_stage.mem_stalling_bit
            ccr_out_selector           => ms_ccr_sel

            -- testing
            tb_controls                => tb_controls,   --> tb
            tb_mem_rd                  => tb_dm_rd,      --> tb
            tb_mem_wr                  => tb_dm_wr,      --> tb
            tb_mem_data_in             => tb_dm_data_in, --> tb
            tb_mem_adr                 => tb_dm_adr,     --> tb
            tb_mem_data_out            => tb_dm_data_out --> tb
        );

    -- ccr = memory_stage.ccr or execute_stage.ccr or tb.ccr
    ccr <= tb_ccr_in when tb_controls = '1'
        else ms_ccr when ms_ccr_sel = '1'
        else xs_ccr;

    tb_ccr_out <= ccr;

    m_w_buffer : entity work.m_w_buffer
        port map(
            --IN
            clk               <= clk,

            in_aluout         <= ms_mwb_aluout,              --> memory_stage.alu_output
            in_mem            <= ms_mwb_mem_input,           --> memory_stage.memory_out
            in_opcode         <= ms_mwb_opcode,              --> memory_stage.opCode_out
            in_destination_0  <= ms_mwb_dest_0_adr,          --> memory_stage.destination_register_1_out
            in_destination_1  <= ms_mwb_dest_1_adr,          --> memory_stage.destination_register_2_out
            in_dest_value_0   <= ms_rf_mwb_dest_1_value_out, --> memory_stage.destination_1_value_out
            in_dest_value_1   <= ms_rf_mwb_dest_2_value_out, --> memory_stage.destination_2_value_out
            in_interrupt      <= xmb_ms_mwb_interrupt,       --> x_m_buffer.out_interrupt
            --OUT
            -- out_aluout        <= TODO,                       --> wb_stage.TODO
            -- out_mem           <= TODO,                       --> wb_stage.TODO
            -- out_opcode        <= TODO,                       --> wb_stage.TODO
            -- out_destination_0 <= TODO,                       --> wb_stage.TODO
            -- out_destination_1 <= TODO,                       --> wb_stage.TODO
            -- out_dest_value_0  <= TODO,                       --> wb_stage.TODO
            -- out_dest_value_1  <= TODO,                       --> wb_stage.TODO
            -- out_interrupt     <= TODO                        --> wb_stage.TODO
        );

    --TODO: wb_stage
end architecture;