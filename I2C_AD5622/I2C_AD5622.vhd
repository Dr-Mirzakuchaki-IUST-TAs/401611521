----------------------------------------------------------------------------------
-- AD5622 (I2C)
-- Zahra Davarzani
-- 2021
----------------------------------------------------------------------------------
-- Library
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
----------------------------------------------------------------------------------
entity I2C_AD5622 is
	PORT(
			clk               : IN       STD_LOGIC;	-- Fpga clk = 80 MHz
			Reset             : IN       STD_LOGIC;	-- Fpga reset 
			Enable            : IN       STD_LOGIC;	-- If Enable = '1' the i2c communication will be active and generate SCL
			RW                : IN       STD_LOGIC;	-- Define write mode or read mode if  RW = 0, mode is write
			RW_CTL            : OUT      STD_LOGIC;	-- Define when we want to write or read if RW_CTL = 0, mode is tansmit
			SCL               : OUT      STD_LOGIC;	-- I2C clock 
			SDA               : INOUT    STD_LOGIC		-- Data line for i2c
		
		);
end I2C_AD5622;

architecture Behavioral of I2C_AD5622 is
	-- I/O internal signal
	SIGNAL Enable_Int  	    : STD_LOGIC      :='0';
	SIGNAL SCL_Int    	    : STD_LOGIC      :='0';
	SIGNAL RW_Int       		 : STD_LOGIC      :='0';
	SIGNAL RW_CTL_Int        : STD_LOGIC      :='0';
	SIGNAL Reset_Int         : STD_LOGIC      :='0';
	-- internal signal
	SIGNAL SCL_Ena           : STD_LOGIC      :='0';  								  	  -- Activate i2c clock when we want i2c
	SIGNAL SDA_clk           : STD_LOGIC      :='0';  									  -- Clock for put data on SDA because setup time and hold time
	SIGNAL SDA_clk_prv       : STD_LOGIC      :='0'; 									  -- Creat risinge edge
	SIGNAL Tx			       : STD_LOGIC      :='1';  									  -- Data that we want to transmit
	SIGNAL Address_RW        : STD_LOGIC_VECTOR (7 DOWNTO 0)   :=(others=> '0'); -- Slave address & read and write bit
	SIGNAL Data_Rx           : STD_LOGIC_VECTOR (7 DOWNTO 0)   :=(others=> '0'); -- Data that recieve from slave
	SIGNAL Data_Rx_2         : STD_LOGIC_VECTOR (7 DOWNTO 0)   :=(others=> '0'); -- Data that recieve from slave
	
	SIGNAL Bit_counter       : unsigned (2 DOWNTO 0) :=(others=> '1');           -- ?ount 0 to 7 
	-- State Machine
	TYPE state_machine   IS (ready, start, command, slave_ack1, wr_8bit_1, wr_8bit_2, rd_8bit_1, rd_8bit_2, slave_ack2, 
									slave_ack3, sack1_del, sack2_del, sack3_del, master_ack1, master_ack2, mack1_del, mack2_del, stop);
	SIGNAL state   : state_machine     := ready;
	-- Constant
	CONSTANT Address  		 : STD_LOGIC_VECTOR (6 DOWNTO 0)    := "0001111";   -- Slave address 00011 &  A1A2(A1 = 1, A2 = 1 ---> refer to datasheet)
	CONSTANT Data_8bit_1     : STD_LOGIC_VECTOR (7 DOWNTO 0)    := "00001101";  -- The fist 8 bit that shouhd transmit on write mode( 0 0 PD1 PD0 D11 D10 D9 D8 (PD1=0, PD0=0 ---> normal mode))
	CONSTANT Data_8bit_2     : STD_LOGIC_VECTOR (7 DOWNTO 0)    := "01010101";  --The second 8 bit that we want to transmit (define by user)

begin
	
	SCL    <= '0' when (SCL_Ena = '1' AND SCL_Int = '0') else '1'; -- Generate i2c clock
   RW_CTL <= RW_CTL_Int; 
	SDA    <= Tx when RW_CTL_Int = '0' else 'Z'; -- When master are on write mode (RW_CTL_Int = '0'), master transmit Tx on SDA otherwise SDA is 'Z' and get amount from slave (here is from testbench)
	Reset_Int <= Reset;
	
	Generate_SCL_SDA_clock: process(clk)        -- Generate SCL_clk and SDA_clk 
															  -- SCL_clk = 100 KHz (standarde mode)
															  -- Master put data on SDA in Rising edge of SDA_clk 
													 
		variable count : INTEGER RANGE 0 TO 800; -- Fpga clock is 80 MHz and generat on testbench
		
	begin
		
			IF(reset_Int = '0') THEN
				count := 0;
				
			ELSIF(clk'EVENT AND clk = '1') THEN
				SDA_clk_prv <= SDA_clk;  		 -- Detect rising edge of SDA_clk
				IF(count = 799) THEN 				-- (Fpga clock = 80 MHz) / (SCL clock = 100 KHz) = 800 ---> count range is 0 to 799
					count := 0;
				ELSE
					count := count + 1;
				END IF;
			
				CASE count IS
					WHEN 0 TO 199 =>
					
						SCL_Int  <= '0';
						SDA_clk <= '0';
						
					WHEN 200 TO 399 =>
					
						SCL_Int  <= '0';
						SDA_clk <= '1';
						
					WHEN 400 TO 599 =>
					
						SCL_Int  <= '1';
						SDA_clk <= '1';
						
					WHEN OTHERS =>
					
						SCL_Int  <= '1';
						SDA_clk <= '0';
						
				END CASE;
			END IF;
	END PROCESS;
	
	Data_Transmiting_Recieving: process(clk)
	begin
	
		IF (reset_Int = '0') THEN 
		
			state   	   <= ready;
			Enable_Int <= '0';
			RW_CTL_Int  	<= '0';
			Bit_counter 	<= (others => '1');
			Data_Rx     	<= (others => '0');
			
		ELSIF (clk'EVENT AND clk = '1') THEN -- Rising edge of fpga clock
		
			Enable_Int  <= Enable;
			RW_Int 		<= RW;
			
			IF (SDA_clk_prv = '0' AND SDA_clk = '1') THEN -- Rising edge of SDA_clk
			
				CASE state IS 
				
					WHEN ready =>                           -- master/fpga waits on ready state unitl Enable = 1
					
						RW_CTL_Int  	<= '0';               -- If Enable = 1, master wants to write start bit and address bits on slave 
						Bit_counter 	<= (others => '1');   -- Bit_counter = 111 (7 in decimal)
						Data_Rx     	<= (others => '0');   -- Data_Rx = "00000000"
						
						IF (Enable_Int = '1') THEN 
						
							state   	   <= start;
							Tx 			<= '0';               -- creat start bit(start bit = SDA becomes low when SCL is high)
							Address_RW  <= Address & RW_Int;  -- put sddress slave with bit write or bit read in Address_RW
							
						ELSE 
						
							state 		<= ready;             -- If Enable = 0 master/fpga waits on ready state
							Tx 			<= '1';               -- SDA is pull up normally and because master does not want to  write Tx = 1
							Address_RW  <= (others => '0');   -- Address_RW = "00000000" because i2c communication is not active and there is not slave
						
						END IF;
						
					WHEN start =>
						
						state   	   	<= command;
						RW_CTL_Int  	<= '0';               -- Because master wants to write start bit and address bits on slave
						Tx             <= Address_RW (to_integer (Bit_counter)); -- Put the eighth bit of Address_RW on Tx and should put data on previous clock
						Bit_counter 	<= Bit_counter - 1;   -- Bit_counter = 110 
						Address_RW		<= Address_RW;  
						Data_Rx			<= (others => '0');   -- Data_Rx = "00000000"
					
					WHEN command =>                         -- Master waits until Bit_counter = 0 and after that state change to slave_ack1
						
						RW_CTL_Int  	<= '0';
						Tx             <= Address_RW (to_integer (Bit_counter));
						Address_RW		<= Address_RW;
						
						Data_Rx			<= (others => '0');  -- Data_Rx = "00000000"
						IF (Bit_counter = 0) THEN      
							
							state   	   <= slave_ack1;       -- when the all 8 bit send, slave should send acknowledge to master
							Bit_counter <= (others => '1');  -- Bit_counter = 111 (7 in decimal)
						
						ELSE
							
							state   	   <= command;
							Bit_counter <= Bit_counter - 1;
						
						END IF;
					
					WHEN slave_ack1 =>
						
						state   	   <= sack1_del;            -- In 9th clock we should see acknowlegde so in 8th clock change the state 
						RW_CTL_Int  	<= '1';               -- Because slave wants to write acknowkedge bit on ADS line that means master wants to read
						Tx             <= '1';               -- Set acknowledge bit on sda by reciever(here by testbench)
						Bit_counter 	<= (others => '1');   -- Bit_counter = 111 (7 in decimal)
						Address_RW		<= Address_RW; 
						Data_Rx			<= (others => '0');   -- Data_Rx = "00000000"
					
					WHEN sack1_del =>                       -- On this state acknowledge bit has seen by master
						
						Bit_counter <= Bit_counter - 1;
						Address_RW		<= Address_RW;
						
						IF (Address_RW(0) = '0') THEN        -- If Address_RW(0) = 0, mode is write
							
							state   	   <= wr_8bit_1;
							RW_CTL_Int  	<= '0';            -- Mode is write
							Tx             <= Data_8bit_1 (to_integer (Bit_counter)); -- Write the first bit on sda when RW_CTL_Int = 0 master trnsmites data to slave
							Data_Rx			<= (others => '0'); -- Data_Rx = "00000000"
						
						ELSE									        -- If Address_RW(0) = 1, mode is read
							
							state   	   <= rd_8bit_1; 
							RW_CTL_Int  	<= '1';             -- Mode is read
							Tx             <= '1';             -- Master reads data from SDA line (here from testbench)
							Data_Rx (to_integer (Bit_counter))  <= SDA; -- Read the first bit from SDA line when RW_CTL_Int = 1 slave trnsmites data to mastre
						
						END IF;
					
					WHEN wr_8bit_1 =>                        -- Write the first 8 bits on slave
						
						RW_CTL_Int  	<= '0';                -- Mode is write
						Tx             <= Data_8bit_1 (to_integer (Bit_counter)); -- Put data on SDA line
						Address_RW		<= Address_RW;
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
						
						IF (Bit_counter = 0) THEN
							
							state   	   <= slave_ack2;         -- when the all 8 bits send, slave should send acknowledge to master
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						
						ELSE
							
							state   	   <= wr_8bit_1;          -- If Bit_counter \= 0, stay on wr_8bit_1 state
							Bit_counter <= Bit_counter - 1;
						
						END IF;
					
					WHEN slave_ack2 =>
						
						state   	   <= sack2_del;             -- State changes to sack2_del 
						RW_CTL_Int  	<= '1';                -- Mode is read
						Tx             <= '1'; 
						Bit_counter 	<= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						Address_RW		<= Address_RW; 
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
					
					WHEN sack2_del =>
						
						state   	   <= wr_8bit_2;             -- State changes to wr_8bit_2 because master wants to write the second 8 bits 
						Bit_counter <= Bit_counter - 1;
						RW_CTL_Int  	<= '0';                -- Mode is write
						Tx             <= Data_8bit_2 (to_integer (Bit_counter)); -- Put data on SDA line
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
   				
					WHEN wr_8bit_2 =>                        -- Write the second 8 bits on slave
						
						RW_CTL_Int  	<= '0';                -- Mode is write
						Tx             <= Data_8bit_2 (to_integer (Bit_counter));
						Address_RW		<= Address_RW;
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
						
						IF (Bit_counter = 0) THEN
							state   	   <= slave_ack3;         -- when the all 8 bits send, slave should send acknowledge to master
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						
						ELSE
							
							state   	   <= wr_8bit_2;          -- If Bit_counter \= 0, stay on wr_8bit_1 state
							Bit_counter <= Bit_counter - 1;
						
						END IF;
					
					WHEN slave_ack3 =>
						
						state   	   <= sack3_del;             -- State changes to sack3_del
						RW_CTL_Int  	<= '1';                -- Mode is read
						Tx             <= '1'; 
						Bit_counter 	<= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						Address_RW		<= Address_RW; 
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
				
					WHEN sack3_del =>
						
						Bit_counter <= Bit_counter - 1;
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
						
						IF (Enable_Int = '1') THEN            -- If Enable_Int = 1 communication 
							
							Address_RW <= Address & RW_Int;   
							
							IF (Address_RW = Address & RW_Int) THEN 
								
								state   	   <= wr_8bit_1;       -- Stay on wr_8bit_1 state
								RW_CTL_Int  	<= '0';          -- Mode is write
								Tx             <= Data_8bit_1 (to_integer (Bit_counter));
								Bit_counter <= Bit_counter - 1;
							
							ELSE
								
								state   	   <= start;           -- State changes to start
								RW_CTL_Int  	<= '1';          -- Mode is read
								Tx             <= '1';
								Bit_counter <= (others => '1'); -- Bit_counter = 111 (7 in decimal)
							
							END IF;
						
						ELSE                                  -- If Enable_Int \= 1, State changes to stop 
							
							state   	   <= stop;
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
							Address_RW <= (others => '0');     -- Address_RW = "00000000"
							Data_Rx <=	(others => '0');       -- Data_Rx = "00000000"
						
						END IF;
					
					WHEN rd_8bit_1 =>                        -- Read the first 8 bits on slave
						
						RW_CTL_Int  	<= '1';                -- when we want recive data or read data from slave
						Tx             <= '1';                -- set data from testbench
						Address_RW		<= Address_RW;
						Data_Rx (to_integer (Bit_counter))  <= SDA; --Data that master reads from slave store in Data_Rx
						
						IF (Bit_counter = 0) THEN
							
							state   	   <= master_ack1;        -- State changes to master_ack1
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						
						ELSE
							
							state   	   <= rd_8bit_1;          -- If Bit_counter \= 0, stay on rd_8bit_1
							Bit_counter <= Bit_counter - 1;
						
						END IF;
					
					WHEN master_ack1 =>
						
						state   	   <= mack1_del;
						RW_CTL_Int  	<= '0';                -- Mode is write beacause master wants to creat acknowledge
						Tx             <= '0';                -- SDA line becomes low by master because of acknowledge bit 
						Bit_counter 	<= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						Address_RW		<= Address_RW; 
						Data_Rx			<= Data_Rx; 
					
					WHEN mack1_del =>
						
						state   	   <= rd_8bit_2;             -- State changes to rd_8bit_2 because master wants to read the second 8 bits
						Bit_counter <= Bit_counter - 1;
						RW_CTL_Int  	<= '1';                -- Mode is read
						Tx             <= '1';
						Data_Rx_2 (to_integer (Bit_counter))  <= SDA;
					
					WHEN rd_8bit_2 =>
						
						RW_CTL_Int  	<= '1';                -- when we want recive data or read data from slave
						Tx             <= '1';                -- set data from test bench
						Address_RW		<= Address_RW;
						Data_Rx_2 (to_integer (Bit_counter))  <= SDA; -- Data that master reads from slave store in Data_Rx_2
						
						IF (Bit_counter = 0) THEN
							
							state   	   <= master_ack2;        -- State changes to master_ack2
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						
						ELSE
							
							state   	   <= rd_8bit_2;          -- If Bit_counter \= 0, stay on rd_8bit_2
							Bit_counter <= Bit_counter - 1;
						
						END IF;
					
					WHEN master_ack2 =>
						
						state   	   <= mack2_del;
						RW_CTL_Int  	<= '0';                -- Mode is write beacause master wants to creat acknowledge
						Tx             <= '1';                -- SDA line becomes high by master because of no acknowledge bit (refer to datasheet)
						Bit_counter 	<= (others => '1');    -- Bit_counter = 111 (7 in decimal)
						Address_RW		<= Address_RW; 
						Data_Rx			<= Data_Rx;	
						Data_Rx_2		<= Data_Rx_2;
					
					WHEN mack2_del =>
						
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
						
						IF (Enable_Int = '1') THEN
							
							Address_RW <= Address & RW_Int;   
							
							IF (Address_RW = Address & RW_Int) THEN
								
								state   	   <= rd_8bit_1;       -- Stay on rd_8bit_1 state
								RW_CTL_Int  	<= '1';          -- Mode is read
								Tx             <= '1'; 
								Bit_counter <= Bit_counter - 1;
								Data_Rx (to_integer (Bit_counter))  <= SDA;
							
							ELSE
								
								state   	   <= start;
								RW_CTL_Int  	<= '0';          -- Mode is write because master wants send start bit
								Tx             <= '0';          -- SDA line becomes low by master because of start bit
								Bit_counter <= (others => '1'); -- Bit_counter = 111 (7 in decimal)
								Data_Rx			<= (others => '0'); -- Data_Rx = "00000000"
								Data_Rx_2		<= (others => '0'); -- Data_Rx_2 = "00000000"
							
							END IF;
						
						ELSE                                  -- If Enable_Int \= 1, State changes to stop
							
							state <= stop;
							RW_CTL_Int  	<= '0';             -- Mode is write because send stop bit by master(reciever)
							Tx             <= '0';             -- As mentioned in datasheet SDA line should become low between no acknowledge bit and stop bit
							Bit_counter <= (others => '1');    -- Bit_counter = 111 (7 in decimal)
							Address_RW 	<= (others => '0');    -- Address_RW = "00000000"
							Data_Rx			<= (others => '0'); -- Data_Rx = "00000000"
						
						END IF;
					
					WHEN stop =>
						
						state <= ready;
						Bit_counter <= (others => '1');       -- Bit_counter = 111 (7 in decimal)
						Address_RW 	<= (others => '0');       -- Address_RW = "00000000"
						Data_Rx			<= (others => '0');    -- Data_Rx = "00000000"
					
				END CASE;
			
			ELSIF (SDA_clk_prv = '1' AND SDA_clk = '0') THEN -- falling edge  SDA_clk
				
				CASE state IS
					
					WHEN start =>
						
						IF (SCL_Ena = '0') THEN
							SCL_Ena <= '1';                    -- allow to generate SCL_clk 
						
						ELSE
							
							NULL;
						
						END IF;
					
					WHEN stop =>
						
						SCL_Ena <= '0';                       -- will not generte SCLC_clk
						RW_CTL_Int  	<= '0';                -- Mode is write because master wants to write stop bit on sda
						Tx             <= '1';	              -- Set 1 on sda because of stop bit (stop bit = SDA becomes high when SCL is high)
					
					WHEN OTHERS =>
						
						NULL;
				
				END CASE;
			END IF;
		END IF;
	END PROCESS;

end Behavioral;

