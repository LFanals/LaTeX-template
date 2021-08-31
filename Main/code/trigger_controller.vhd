library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

------------------------------------------
------------------------------------------
--
-- trigger_controller.vhd
-- Hardware controller for the trigger controller
-- Clock frequency required: 108 MHz
-- Resetn: active low
--
------------------------------------------
------------------------------------------


entity trigger_controller is
port(
	clk:  	in std_logic; -- 108 MHz clock signal
    resetn: in std_logic; -- active low
    sample_ready: in std_logic; -- 1 clock pulse that denotes new input data
    data1: in std_logic_vector(11 downto 0); -- input data from the ADC
    trigger_up: in std_logic; -- asynchronous input from button, to increase the trigger level
    trigger_down: in std_logic; -- asynchronous input from button, to decrease the trigger level
    trigger_n_p: in std_logic; -- asynchronous input from button, to invert trigger slope
    vsync: in std_logic; -- display vsync signal, used for the trigger condition
    vscale: in std_logic_vector(1 downto 0); -- asynchronous input from switches, to adjust the scale
    hscale: in std_logic_vector(1 downto 0); -- horitzontal scale
    period: out std_logic_vector(10 downto 0); -- number of pixels to represent the period
    offset: out std_logic_vector(7 downto 0); -- center displayed signal
    we: out std_logic; -- write enable for the memory
    addr_out: out std_logic_vector(10 downto 0); -- memory address in which to write data_out
    data_out: out std_logic_vector(11 downto 0); -- data to write to the memory
    trigger_level: out std_logic_vector(8 downto 0) -- current trigger_level, to display in screen
);
end trigger_controller;

architecture arch of trigger_controller is
    signal trigger_value: std_logic_vector(8 downto 0) := (8 => '1', others => '0'); -- only 9 MSB used
    signal prev_value: std_logic_vector(11 downto 0); -- captures the previous acquired value, needed for the trigger
    signal last_value: std_logic_vector(11 downto 0); -- captures the last acquired value
    signal counted_acqs: std_logic_vector(10 downto 0); -- from 0 to 1279
    
    signal trigger_slope: std_logic := '1'; -- positive slope by default
    signal trigger_flag: std_logic; -- 0 if idle, 1 if in acquistion
    signal wee: std_logic; -- internal we signal
    
    -- buttons process signals
    signal up, upp, uppp: std_logic;
    signal down, downn, downnn: std_logic;
    signal slope, slopee, slopeee: std_logic;
    signal vscale_r, vscale_rr: std_logic_vector(1 downto 0);
    signal hscale_r, hscale_rr: std_logic_vector(1 downto 0);
    signal hscale_counter: std_logic_vector(1 downto 0);
    
    -- period signals
    signal flag_second_cross: std_logic;
begin

    
main: process(clk)
begin
    if (clk'event and clk='1') then
        if (resetn = '0') then -- sync reset
            prev_value <= (others => '0');
            last_value <= (others => '0');
            counted_acqs <= (others => '0');
            trigger_flag <= '0';
            wee <= '0';
        else
        
            -- trigger condition
            if ((vsync='0' and counted_acqs=0 and trigger_flag='0')) then
                if ((trigger_slope='1' and last_value(11 downto 3)>trigger_value(8 downto 0) and prev_value(11 downto 3)<trigger_value(8 downto 0) and last_value(11 downto 8)>prev_value(11 downto 8)) or
                    (trigger_slope='0' and last_value(11 downto 3)<trigger_value(8 downto 0) and prev_value(11 downto 3)>trigger_value(8 downto 0) and last_value(11 downto 8)<prev_value(11 downto 8))) then -- trigger fires
                    trigger_flag <= '1'; -- flag that determines that a total of 1280 samples need to be acquired
                    -- already output the first sample
                    counted_acqs <= (others => '0'); -- the first address is 0
                    wee <= '1';
                    hscale_counter <= (others => '0');
                end if;
            end if;    

            -- acquistion
            if (sample_ready = '1') then -- rising edge, sample_ready is 1 clk period wide
                last_value <= data1; -- acquire every new sample, it's needed to determine if trigger is fired
                prev_value <= last_value; -- register
                hscale_counter <= hscale_counter + '1';
                if (trigger_flag = '1' and hscale_counter = hscale_rr) then -- this performs the horitzontal scale, take 1 out of hscale_rr samples
                    hscale_counter <= (others => '0');
                    wee <= '1'; -- write to memory
                    counted_acqs <= counted_acqs + '1';
                    if (counted_acqs = 1279) then
                        trigger_flag <= '0'; -- 1279 is the last sample, 0 to 1279
                    end if;
                end if;
            end if;
            
            -- detect the second time in which the trigger condition is met, so as to get the period of the signal
            -- use prev_value(11 downto 3)<=trigger_value(8 downto 0) and prev_value(11 downto 3)>=trigger_value(8 downto 0)
            -- to avoid counting 2 or more periods in case a sample is equal to the trigger level
            if ((trigger_flag='1' and flag_second_cross='0' and counted_acqs>0 and trigger_slope='1' and last_value(11 downto 3)>trigger_value(8 downto 0) and prev_value(11 downto 3)<=trigger_value(8 downto 0)) 
                or (trigger_flag='1' and flag_second_cross='0' and counted_acqs>0 and trigger_slope='0' and last_value(11 downto 3)<trigger_value(8 downto 0) and prev_value(11 downto 3)>=trigger_value(8 downto 0))) then
                flag_second_cross <= '1';
                period <= counted_acqs;
            end if;

            -- clear counted_acqs and flag for the period measurement
            if (counted_acqs = 1280) then
                counted_acqs <= (others => '0');
                flag_second_cross <= '0';
            end if;
            
            -- guarantee only 1 clock period width at we
            if (wee = '1') then
                wee <= '0';
            end if;

        end if;
    end if;
end process;


outputs: process(clk)
begin
    if (clk'event and clk='1') then
        if (resetn = '0') then -- sync reset
            addr_out <= (others => '0');
            data_out <= (others => '0');
            trigger_level <= (others => '0');
            we <= '0';
        else
            addr_out <= counted_acqs;
            case (vscale_rr) is -- shift right, offset is wired to the vga to center the waveform
                when "00" => data_out <= last_value; -- dont modify the signal
                             offset <= (others => '0');
                when "01" => data_out <= "0" & last_value(11 downto 1); -- scale /2
                             offset <= "10000000";
                when "10" => data_out <= "00" & last_value(11 downto 2); -- scale /4
                             offset <= "11000000";
                when "11" => data_out <= "000" & last_value(11 downto 3); -- scale /8
                             offset <= "11100000";
            end case;
            trigger_level <= trigger_value;
            we <= wee;
        end if;
    end if;
end process;


buttons_acq: process(clk) -- 2 shift registers used for each button
begin
    if (clk'event and clk='1')then
        if (resetn = '0') then
            trigger_value <= (8 => '1', others => '0');
            trigger_slope <= '1';
        else
            up <= trigger_up; -- get asynchronous input
            upp <= up; -- second register
            uppp <= upp; -- third register
            if (uppp='0' and upp='1') then -- button rising edge 
                trigger_value <= trigger_value + "000010000"; -- add 16
            end if;
            down <= trigger_down; -- get asynchronous input
            downn <= down; -- second register
            downnn <= downn; -- third register
            if (downnn='0' and downn='1') then -- button rising edge
                trigger_value <= trigger_value - "000010000"; -- substract 16
            end if;
            slope <= trigger_n_p; -- get asynchronous input
            slopee <= slope; -- second register
            slopeee <= slopee; -- third register
            if (slopeee='0' and slopee='1') then -- button rising edge
               trigger_slope <= not trigger_slope; -- invert trigger slope
            end if;
            vscale_r <= vscale; -- get asynchronous vertical scale input
            vscale_rr <= vscale_r; -- second register
            hscale_r <= hscale; -- get asynchronous horitzontal scale input
            hscale_rr <= hscale_r; -- second register
        end if;
    end if;
end process;


end arch;
