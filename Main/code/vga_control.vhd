library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

------------------------------------------
------------------------------------------
--
-- vga_control.vhd
-- Generates the necessary signals to display data on screen
-- For each column pixel, it reads its value at the memory. 
-- If the 9 MSB coindice with the current row, a yellow pixel is plotted.
-- Trigger level is also plotted in a 30 wide pixel blue line.
-- Clock frequency required: 108 MHz
-- Resetn: active low
--
------------------------------------------
------------------------------------------


entity vga_control is
port(
	clk:  	in std_logic; -- 108 MHz
	resetn: in std_logic; -- active low
	data_in: in std_logic_vector(11 downto 0); -- input data from the memory
	trigger_level: in std_logic_vector(8 downto 0); -- trigger level to display
	--
    t_temperature: in std_logic_vector(10 downto 0); -- threshold temperature, in pixels
    temperature: in std_logic_vector(10 downto 0); -- current temperature, in pixels
    alarm: in std_logic; -- alarm, 1 if true
    period: in std_logic_vector(10 downto 0); -- number of pixels to represent the period
    offset: in std_logic_vector(7 downto 0); -- center displayed signal
    --
	vsync:  out std_logic; -- vsync signal for the VGA
	hsync:  out std_logic; -- hsync signal for the VGA
	red: 	out std_logic_vector(3 downto 0); -- sets the red color at each pixel, from 0 to 15
	green:  out std_logic_vector(3 downto 0); -- sets the green color at each pixel, from 0 to 15
	blue:   out std_logic_vector(3 downto 0); -- sets the blue color at each pixel, from 0 to 15
	addr_out: out std_logic_vector(10 downto 0) -- memory address to read
);
end vga_control;

architecture arch of vga_control is
	type states is (retrace, back, actpixels, front); -- states needed for both hsync and vsync processes
	signal h_state : states;
	signal v_state : states;
	signal h_counter : std_logic_vector(10 downto 0); -- counter for the hsync process, to count clock periods
    signal v_counter : std_logic_vector(10 downto 0); -- counter for the vsync process, to count clock periods
	signal hhsync : std_logic; -- internal hsync signal
    signal hhsync_prev : std_logic; -- hhsync_prev is also registered and stores the previous hhsync value to detect a rising edge on hsync
begin


hsync_process: process(clk) -- hsync process
begin
    if (clk='1' and clk'event) then
        if (resetn='0') then
            h_counter <= (others => '0'); 
            h_state <= retrace;
        else
			h_counter <= h_counter + 1; -- 
			case (h_state) is
				when retrace =>	if (h_counter = 112 - 1) then
									h_state <= back;
									h_counter <= (others => '0');
								end if;
				when back =>	if (h_counter = 248 - 1) then
									h_state <= actpixels;
									h_counter <= (others => '0');
								end if;
				when actpixels =>	if (h_counter = 1280 - 1) then
										h_state <= front;
										h_counter <= (others => '0');
									end if;
				when front =>	if (h_counter = 48 - 1) then
										h_state <= retrace;
										h_counter <= (others => '0');
									end if;
			end case;
		end if;
	end if;
end process;

hhsync <= '0' when h_state = retrace else -- hsync can only be 0 in retrace, if not it must be 1
		  '1';

vsync_process: process(clk) -- vsync process
begin
 
    if (clk='1' and clk'event) then
        if (resetn='0') then
            v_counter <= (others => '0'); 
            v_state <= retrace;
        elsif (hhsync = '0' and hhsync_prev = '1') then
            v_counter <= v_counter + 1;
            case (v_state) is
                when retrace =>	if (v_counter = 3 - 1) then
                                    v_state <= back;
                                    v_counter <= (others => '0'); -- each state change, clear the counter
                                end if;
                when back =>	if (v_counter = 38 - 1) then
                                    v_state <= actpixels;
                                    v_counter <= (others => '0');
                                end if;
                when actpixels =>	if (v_counter = 1024 - 1) then
                                        v_state <= front;
                                        v_counter <= (others => '0');
                                    end if;
                when front =>	if (v_counter = 1 - 1) then
                                        v_state <= retrace;
                                        v_counter <= (others => '0');
                                    end if;
            end case;
        end if;
    end if;
end process;

		   
output_process: process (clk) -- output registers
begin
    if (clk='1' and clk'event) then
        if (resetn='0') then
            vsync <= '1';
            hsync <= '1';
            hhsync_prev <= '1';
            red <= "0000";
            green <= "0000";
            blue <= "0000";
        else
			hhsync_prev <= hhsync; -- register hhsync, in order to detect a falling edge
			if (h_state = retrace) then
                 hsync <= '0';
            else
                 hsync <= '1';
            end if;
			if (v_state = retrace) then
			     vsync <= '0';
			else
			     vsync <= '1';
			end if;

			
			-- if in the first clock a new addr_out is requested, memory will answer in the second clock, and this entity will receive it in the third clock rising edge, in data_in bus
			-- because of this, this third clock should coincide with the first active pixel, i.e., h_counter=0
			if (h_state = back and h_counter = 248 - 2) then -- next h_state will be active_pixels
			     addr_out <= (others => '0');
			elsif (h_state = back and h_counter = 248 - 1) then
			     addr_out <= (0 => '1', others => '0');
            else
                 addr_out <= h_counter(10 downto 0) + 2;
			end if;
			
			-- plot
			if (h_state = actpixels and v_state = actpixels) then
                 if (h_counter < 30 and (v_counter(8 downto 0) = trigger_level) and v_counter(9)='0' and alarm = '0') then -- plot trigger line in blue, 30 pixels wide
                         red <= "0000";
                         green <= "0000";
                         blue <= "1111";
			     elsif ( (data_in(11 downto 3)+offset = v_counter(8 downto 0)) and v_counter(9)='0' and alarm='0') then -- compare 9 MSB, plot the waveform in yellow
			         -- waveform is shifted to have it centered in the upper half of the screen
			         red <= "1111";
			         green <= "1111";
			         blue <= "0000";
			     elsif (v_counter > 511+10 and v_counter < 511+20 and h_counter < period and alarm='0') then -- plot period bar, red
                         red <= "1111";
                         green <= "0000";
                         blue <= "0000"; 
			     elsif (v_counter > 511+30 and v_counter < 511+61+5 and h_counter = t_temperature) then -- plot temperature threshold in blue
			             red <= "0000";
                         green <= "0000";
                         blue <= "1111";  
			     elsif (v_counter > 511+30 and v_counter < 511+61 and h_counter < temperature) then -- plot temperature bar
			         if (alarm = '0') then -- in green
                         red <= "0000";
                         green <= "1111";
                         blue <= "0000";  
			         else -- in red
                         red <= "1111";
                         green <= "0000";
                         blue <= "0000";  
			         end if;
			     else -- don't plot
			         red <= "0000";
                     green <= "0000";
                     blue <= "0000";    
			     end if;
			else -- don't plot
                red <= "0000";
                green <= "0000";
                blue <= "0000";  
            end if;  
            
            
		end if;
	end if;
end process;
end arch;
 
