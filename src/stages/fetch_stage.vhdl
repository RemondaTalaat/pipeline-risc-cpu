library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;

entity fetch_stage is
    port (
        clk                          : in std_logic;
        rst                          : in std_logic;

        in_interrupt                 : in std_logic;
        in_if_flush                  : in std_logic;
        in_stall                     : in std_logic;
        in_parallel_load_pc_selector : in std_logic;
        in_loaded_pc_value           : in std_logic_vector(31 downto 0);
        in_branch_address            : in std_logic_vector(31 downto 0);
        in_hashed_address            : in std_logic_vector(3 downto 0);

        out_interrupt                : out std_logic;
        out_inst_length_bit          : out std_logic; -- 16 or 32 bits
        out_instruction_bits         : out std_logic_vector(31 downto 0);
        out_predicted_address        : out std_logic_vector(31 downto 0);
        out_hashed_address           : out std_logic_vector(3 downto 0);
        out_inc_pc                   : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of fetch_stage is
    signal pc           : std_logic_vector(31 downto 0);
    signal len_bit      : std_logic                     := '0';
    signal mem_rd       : std_logic                     := '1';
    signal mem_wr       : std_logic                     := '0';
    signal mem_data_in  : std_logic_vector(15 downto 0) := (others => '0');
    signal mem_data_out : std_logic_vector(15 downto 0) := (others => '0');
begin
    inst_mem : entity work.instr_mem(rtl)
        generic map(ADR_LENGTH => 32)
        port map(
            clk      => clk,
            rd       => mem_rd,
            wr       => mem_wr,
            rst      => rst,
            data_in  => mem_data_in,
            address  => pc,
            data_out => mem_data_out
        );

    out_inc_pc <= to_vec(to_int(pc) + 1, out_inc_pc'length);

    -- TODO
    --out_interrupt <= ???

    -- TODO
    --out_predicted_address <= ???

    -- TODO
    --out_hashed_address <= ???

    process (clk, rst)
    begin
        if rst = '1' then
            null;
        elsif falling_edge(clk) then
            -- decide PC next address
            if in_if_flush = '1' then
                pc <= (others => '0'); -- to be corrected
            elsif in_parallel_load_pc_selector = '1' then
                pc <= (others => '0'); -- to be corrected
            elsif rst = '1' then
                pc <= (others => '0'); -- to be corrected
            elsif mem_data_out(14 downto 8) = OPC_CALL then
                pc <= (others => '0'); -- to be corrected
            elsif (in_stall = '1' or in_interrupt = '1') then
                pc <= (others => '0'); -- to be corrected
            else
                pc <= std_logic_vector(unsigned(pc) + 1);
            end if;
            -- decide whether the instruction is 32 or 64 bits
            if mem_data_out(0) = '1' then
                out_inst_length_bit <= '1';
                len_bit             <= '1';
            else
                out_inst_length_bit <= '0';
                len_bit             <= '0';
            end if;
            -- instruction output
            if len_bit = '0' then
                out_instruction_bits(31 downto 16) <= mem_data_out;
                out_instruction_bits(15 downto 0)  <= (others => '0');
            else
                out_instruction_bits(15 downto 0) <= mem_data_out;
            end if;
        end if;
    end process;
end architecture;