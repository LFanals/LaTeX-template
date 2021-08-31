library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

------------------------------------------
------------------------------------------
--
-- Testbench for the acquire_and_plot entity
-- The acquire_and_plot entity is under acquire_and_plot.vhd
--
------------------------------------------
------------------------------------------


entity acquire_and_plot_tb is

end acquire_and_plot_tb;


architecture behaviour of acquire_and_plot_tb is

-- Declaration of the output signal of the behaviour of acquire_and_plot
signal ncs: std_logic;
signal sclk: std_logic;
signal vsync: std_logic;
signal hsync: std_logic;
signal red: std_logic_vector(3 downto 0);
signal green: std_logic_vector(3 downto 0);
signal blue: std_logic_vector(3 downto 0);

-- Declaration of the input signals of the behaviour of acquire_and_plot
signal clk: std_logic:= '0'; -- 108 MHz
signal resetn: std_logic:= '0'; -- active low
signal sdata1: std_logic:= '0';
signal trigger_up: std_logic:= '0';
signal trigger_down: std_logic:= '0';
signal trigger_n_p: std_logic:= '0';
--
signal t_temperature: std_logic_vector(10 downto 0):= (10 => '1', others => '0'); -- threshold temperature, in pixels
signal temperature: std_logic_vector(10 downto 0):= (10 => '1', 9 => '1', others => '0'); -- current temperature, in pixels
signal alarm: std_logic := '0'; -- alarm, 1 if true
signal vscale: std_logic_vector(1 downto 0) := (others => '0'); -- vertical scale
signal hscale: std_logic_vector(1 downto 0) := (others => '0'); -- horitzontal scale
--

-- Auxiliary signals
signal dataa: std_logic_vector(11 downto 0):= (others => '0');

component acquire_and_plot
port(
	clk:  	in std_logic; -- 108 MHz
    resetn: in std_logic; -- active low
    sdata1: in std_logic; -- adc input data
    trigger_up: in std_logic; -- trigger up button
    trigger_down: in std_logic; -- trigger down button
    trigger_n_p: in std_logic; -- trigger switch mode button
 	--
    t_temperature: in std_logic_vector(10 downto 0); -- threshold temperature, in pixels
    temperature: in std_logic_vector(10 downto 0); -- current temperature, in pixels
    alarm: in std_logic; -- alarm, 1 if true
    vscale: in std_logic_vector(1 downto 0); -- vertical scale
    hscale: in std_logic_vector(1 downto 0); -- horitzontal scale
    --   
    ncs: out std_logic; -- adc chip select
    sclk: out std_logic; -- slow clock for the adc
    vsync: out std_logic; -- vsync signal for the VGA
    hsync: out std_logic; -- hsync signal for the VGA
    red: out std_logic_vector(3 downto 0); -- sets the red color at each pixel, from 0 to 15
    green: out std_logic_vector(3 downto 0); -- sets the green color at each pixel, from 0 to 15
    blue: out std_logic_vector(3 downto 0) -- sets the blue color at each pixel, from 0 to 15
);
end component;



begin

	-- Process that creates the clock signal
	clk_process: process
	begin
		wait for 4.629629629 ns; -- adjust 108 MHz
		clk <= not clk;
	end process;
	
	-- Generation of the reset signal
	resetn <= '0' after 12 ns, '1' after 22 ns;
	
	adc: process
        variable counter: integer range 0 to 15;
	begin
	
	    sdata1 <= 'Z';
        wait until ncs = '0';
        for counter in integer range 0 to 14 loop
            wait until sclk = '0'; 
            wait for 20 ns; -- t4
            if (counter >= 3) then
                sdata1 <= dataa(11-counter+3); -- pass bit
            else
                sdata1 <= '0';
            end if;       
        end loop;
        wait until sclk = '0';
        wait for 25 ns; -- t8
        dataa <= dataa + 1024; -- increase data by a lot, so trigger triggers

	end process;
	
	-- Temperature and temperature threshold static values
    temperature_procces: process
    begin
        t_temperature <= t_temperature - 16; -- 50 degrees
        temperature <= temperature - 16;
        wait for 1 ms;
        t_temperature <= t_temperature + 16; -- 50 degrees
        temperature <= temperature + 16;
        wait for 1 ms;
    end process;
    
    -- Alarm
    alarm_process: process
    begin
        wait for 10 ms;
        alarm <= '1';
        wait for 30 ms;
        alarm <= '0';
    end process;
	
	
	buttons: process
    begin
    
        -- wait for 1 ms;
        -- trigger_up <= not trigger_up;

    end process;
	
	
	-- Component instantiation
	acquire_and_plot_instance: acquire_and_plot
	port map(
				clk 	=> clk,
				resetn 	=> resetn,
                sdata1  => sdata1,
                trigger_up => trigger_up,
                trigger_down => trigger_down,
                trigger_n_p => trigger_n_p,
                t_temperature => t_temperature,
                temperature => temperature,
                alarm => alarm,
                vscale => vscale,
                hscale => hscale,
                ncs => ncs,
                sclk => sclk,
                vsync => vsync,
                hsync => hsync,
                red => red,
                green => green,
                blue => blue
	);
	
end behaviour;
