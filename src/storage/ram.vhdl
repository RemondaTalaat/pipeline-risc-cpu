library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;

entity ram is
    --NUM_WORDS: maximum number (and no more) of words you want the ram to hold.
    --ADR_LENGTH: number of adress bits, ADR_LENGTH <= ceil(log2(NUM_WORDS)).
    --WORD_LENGTH: number of bits of data bus and the word stored in one address in ram.
    generic (NUM_WORDS, WORD_LENGTH, ADR_LENGTH : integer);

    port (
        -- wr: write to ram through data_in
        -- rd: read from ram to data_out
        clk, rd, wr : in std_logic;
        -- rst: async 0 parallel load to all latches
        rst         : in std_logic;
        data_in     : in std_logic_vector(WORD_LENGTH - 1 downto 0);
        address     : in std_logic_vector(ADR_LENGTH - 1 downto 0);
        data_out    : out std_logic_vector(WORD_LENGTH - 1 downto 0)
    );
end entity;

architecture rtl of ram is
    type DataType is array(0 to NUM_WORDS - 1) of std_logic_vector(data_in'range);
    signal data : DataType;
begin
    process (clk, rd, wr, address, data_in, rst)
        -- vhdl cant cast 32bit (but instead 31bits) to integers
        variable safe_adr : std_logic_vector(30 downto 0) := (others => '0');
    begin
        if rst = '1' then
            for i in data'range loop
                data(i) <= to_vec(0, data(i)'length);
            end loop;
        else
            if address'length >= 32 then
                safe_adr := address(30 downto 0);
            else
                safe_adr(address'range) := address;
            end if;

            if unsigned(safe_adr) >= NUM_WORDS then
                report "address=" & to_str(to_int(safe_adr)) & " exceeds NUM_WORDS=" & to_str(NUM_WORDS) severity warning;
            else
                if rd = '1' then
                    data_out <= data(to_int(safe_adr));
                end if;

                if wr = '1' then
                    data(to_int(safe_adr)) <= data_in;
                end if;
            end if;
        end if;
    end process;
end architecture;