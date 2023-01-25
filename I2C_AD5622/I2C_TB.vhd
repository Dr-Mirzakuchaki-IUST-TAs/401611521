
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
 
ENTITY I2C_TB IS
END I2C_TB;
 
ARCHITECTURE behavior OF I2C_TB IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT I2C_AD5622
    PORT(
         clk : IN  std_logic;
         Reset : IN  std_logic;
         Enable : IN  std_logic;
         RW : IN  std_logic;
         RW_CTL : OUT  std_logic;
         SCL : OUT  std_logic;
         SDA : INOUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk : std_logic := '0';
   signal Reset : std_logic := '0';
   signal Enable : std_logic := '0';
   signal RW : std_logic := '0';

	--BiDirs
   signal SDA : std_logic;


 	--Outputs
   signal SCL : std_logic;
	signal RW_CTL : std_logic := '0';

   -- Clock period definitions
   constant clk_period : time := 12.5 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: I2C_AD5622 PORT MAP (
          clk => clk,
          Reset => Reset,
          Enable => Enable,
          RW => RW,
          RW_CTL => RW_CTL,
          SCL => SCL,
          SDA => SDA
        );

   -- Clock process definitions
   clk_process :process
   begin
		clk <= '0';
		wait for clk_period/2;
		clk <= '1';
		wait for clk_period/2;
   end process;
	
   -- Enable Generator
	process
	begin
		Enable <= '0', '1' after 34719 ns, '0' after 63057 ns, '1' after 417480 ns, '0' after 500480 ns;
		wait;
	end process;
	
	-- RW Generator
	process
	begin
		RW <= '0', '1' after 312520 ns, '0' after 502125 ns;
		wait;
	end process;
	
	-- SDA Generator
	SDA <= 'Z' WHEN RW_CTL = '0' ELSE '0';
	
	-- Reset
	Reset <= '1', '0' after 873000 ns;
	
END;
