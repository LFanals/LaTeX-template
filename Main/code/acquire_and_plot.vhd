library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

------------------------------------------
------------------------------------------
--
-- acquire_and_plot.vhd
-- Encapsulate the different designs
-- Acquires a signal and plots it
-- Clock frequency required: 108 MHz
-- Resetn: active low
--
------------------------------------------
------------------------------------------


entity acquire_and_plot is
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
end acquire_and_plot;

architecture arch of acquire_and_plot is
    signal vvsync: std_logic; -- internal vsync signal, must be passed to the trigger controller
    signal sample_ready: std_logic;
    signal data_adc_trigger: std_logic_vector(11 downto 0);
    signal we: std_logic;
    signal addr_trigger_memory: std_logic_vector(10 downto 0);
    signal data_trigger_memory: std_logic_vector(11 downto 0);
    signal trigger_level: std_logic_vector(8 downto 0);
    signal addr_vga_memory: std_logic_vector(10 downto 0);
    signal data_memory_vga: std_logic_vector(11 downto 0);
    signal sdata2: std_logic;
    signal period: std_logic_vector(10 downto 0);
    signal offset: std_logic_vector(7 downto 0);

    component adc_driver is
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
    end component;
    
    component trigger_controller is
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
    end component;
    
    component sync_ram_dualport is
        port(
            clk_in : in std_logic;
            clk_out : in std_logic;
            we : in std_logic ;
            addr_in : in std_logic_vector(10 downto 0) ;
            addr_out : in std_logic_vector(10 downto 0) ;
            data_in : in std_logic_vector(11 downto 0) ;
            data_out : out std_logic_vector(11 downto 0)
        );
    end component;
    
    component vga_control is
        port(
            clk:      in std_logic; -- 108 MHz
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
            red:     out std_logic_vector(3 downto 0); -- sets the red color at each pixel, from 0 to 15
            green:  out std_logic_vector(3 downto 0); -- sets the green color at each pixel, from 0 to 15
            blue:   out std_logic_vector(3 downto 0); -- sets the blue color at each pixel, from 0 to 15
            addr_out: out std_logic_vector(10 downto 0) -- memory address to read
        );
    end component;
    
begin

vsync <= vvsync; -- copy internal vsync signal, vvsync, to output

adc: adc_driver port map     (clk => clk,
                              resetn => resetn,
                              sdata1 => sdata1,
                              sdata2 => sdata2, -- not used
                              ncs => ncs,
                              sclk => sclk,
                              sample_ready => sample_ready,
                              data => data_adc_trigger
);

trigger: trigger_controller port map (clk => clk,
                                      resetn => resetn,
                                      sample_ready => sample_ready,
                                      data1 => data_adc_trigger,
                                      trigger_up => trigger_up,
                                      trigger_down => trigger_down,
                                      trigger_n_p => trigger_n_p,
                                      vsync => vvsync,
                                      vscale => vscale,
                                      hscale => hscale,
                                      period => period,
                                      offset => offset,
                                      we => we,
                                      addr_out => addr_trigger_memory,
                                      data_out => data_trigger_memory,
                                      trigger_level => trigger_level
);

memory: sync_ram_dualport port map (clk_in => clk,
                                    clk_out => clk,
                                    we => we,
                                    addr_in => addr_trigger_memory,
                                    addr_out => addr_vga_memory,
                                    data_in => data_trigger_memory,
                                    data_out => data_memory_vga 
);

vga: vga_control port map (clk => clk,
                           resetn => resetn,
                           data_in => data_memory_vga,
                           trigger_level => trigger_level,
                           t_temperature => t_temperature,
                           temperature => temperature,
                           alarm => alarm,
                           period => period,
                           offset => offset,
                           vsync => vvsync,
                           hsync => hsync,
                           red => red,
                           green => green,
                           blue => blue,
                           addr_out => addr_vga_memory           
);



end arch;
 
