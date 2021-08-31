library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

------------------------------------------
------------------------------------------
--
-- adc_driver.vhd
-- Hardware controller for the A/D converter
-- Provides the digitized input serial signal in a 8 bit output, although the 12 useful bits are stored
-- Clock frequency required: 108 MHz
-- resetn: active low
--
------------------------------------------
------------------------------------------


entity adc_driver is
port(
	clk:  	in std_logic; -- 108 MHz clock signal
	resetn: in std_logic; -- active low
	sdata1: in std_logic; -- serial data 1, comes from the ADC board, it's the one that provides signal
	sdata2: in std_logic; -- serial data 2, comes from the ADC board
	ncs: out std_logic; -- chip select signal for the ADC converters
	sclk: out std_logic; -- slow clock, 108 MHz / 6 = 18 MHz clock for the ADC converters
	sample_ready: out std_logic; -- turns 1 for a clock period to indicate new data is present at the output
	data: out std_logic_vector(11 downto 0) -- output data
);
end adc_driver;

architecture arch of adc_driver is
	type states is (start, t2, readzeros, readbits, tquiet); -- possible states in the conversion
	signal state: states := start; -- initialize state
    signal counter: std_logic_vector(2 downto 0); -- counts the number of clk periods to know when it's time to jump to another state
    signal counter_sclk: std_logic_vector(2 downto 0); -- will count from 0 to 5 in order to generate the slow clock, sclk
    signal counter_bits: std_logic_vector(3 downto 0); -- counts the first 3 useless bits, return to 0, and then counts the 12 useful bits 
    signal dataa: std_logic_vector(11 downto 0); -- internal data
    signal sample_readyy: std_logic; -- internal sample_ready signal
begin


main: process (clk) -- driver
begin
    if (clk'event and clk='1') then
        if (resetn='0') then
            sclk <= '1';
            ncs <= '1';
            counter_bits <= (others => '0');
            sample_readyy <= '0';
        else
            case (state) is
               when start =>        -- set chip select to 0 and move to next state
                                    state <= t2;
                                    ncs <= '0';
                                    counter <= (others => '0');
               when t2 =>           -- wait 2 clock cycles to guarantee t2, then starts acquiring
                                    counter <= counter + 1;
                                    if (counter = 1) then -- waits for 2 clk periods, around 20 ns
                                        state <= readzeros;
                                        counter <= (others => '0');
                                        sclk <= '0';
                                        counter_sclk <= (others => '0');
                                    end if;
                when readzeros =>   -- read the 3 useless bits, datasheet may be confusing
                                    counter_sclk <= counter_sclk + 1; 
                                    if (counter_sclk = 2) then -- sclk rising edge
                                        sclk <= '1';
                                    elsif (counter_sclk = 5) then
                                        sclk <= '0'; -- sclk falling edge
                                        counter_sclk <= (others => '0');
                                        counter_bits <= counter_bits + 1;
                                        if (counter_bits = 3-1) then -- the 3 Z bits have been received
                                            counter_bits <= (others => '0');
                                            state <= readbits;
                                        end if;
                                    end if;
                when readbits  =>   -- read the 12 useful bits
                                    counter_sclk <= counter_sclk + 1; 
                                    if (counter_sclk = 2) then -- sclk rising edge
                                        sclk <= '1';
                                    elsif (counter_sclk = 5) then -- sclk falling edge
                                        sclk <= '0';
                                        counter_sclk <= (others => '0');
                                        counter_bits <= counter_bits + 1;
                                        dataa(11 - to_integer(unsigned(counter_bits))) <= sdata1; -- msb comes first
                                        if (counter_bits = 12-1) then -- all 12 bits received
                                            counter_bits <= (others => '0');
                                            state <= tquiet;
                                            sample_readyy <= '1';
                                            counter <= (others => '0');
                                        end if;
                                    end if;
                when tquiet =>      -- wait for enough time until starting the next conversion
                                    sample_readyy <= '0'; -- 1 period width
                                    counter_sclk <= counter_sclk + 1;
                                    if (counter_sclk = 2) then -- return sclk and ncs to idle (1)
                                        sclk <= '1';
                                        ncs <= '1';
                                    end if;
                                    if (counter_sclk = 7) then -- during 5 clk periods, around 50 ns = tquiet, sclk and ncs have remained idle
                                        state <= start;
                                        counter <= (others => '0');
                                    end if;
            end case;
        end if;
    end if;
end process;


output: process (clk) -- output data register
begin
    if (clk'event and clk='1') then
        if (resetn = '0') then
            data <=  (others => '0');
            sample_ready <= '0';
        else
            if (sample_readyy = '1') then
                data <= dataa;
            end if;
            sample_ready <= sample_readyy;
        end if;
    end if;
end process;

end arch;
 
