library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

------------------------------------------
------------------------------------------
--
-- ddff.vhd
-- two concatenated flip flops
--
------------------------------------------
------------------------------------------


entity ddff is
port(
	clk:  	in std_logic; -- clock signal
    dd: in std_logic; -- input
    q: out std_logic -- output
);
end ddff;

architecture arch of ddff is
    signal qq: std_logic;
begin


outputs: process(clk)
begin
    if (clk'event and clk='1') then
        q <= qq;
        qq <= dd;
    end if;
end process;


end arch;