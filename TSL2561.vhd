--TSL2561
--powerup:00000011
--address:GND(0101001) Float(0111001) VDD(1001001)
--
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity TSL2561 is
	port	(CLK:in std_logic;
			RST:in std_logic;
			ena:in std_logic;
			test_800:out std_logic;
			test_400:out std_logic;
			test_count:out integer;
			state_count:out integer;
			act_done:out std_logic;
			SCL:inout std_logic;
			SDA:inout std_logic
				);
end TSL2561;

architecture TSL of TSL2561 is
type states is	(idle, start, send_address, sending_data, check_ack, send_data, re_start, read_data, send_ack, stop);
signal state,prev_act:states;
type commands is array(0 to 3) of std_logic_vector(7 downto 0);
constant operations:commands:=(
X"80",	--select control register
X"03",	--power on command
X"AC",	--read light intensity	channel 0
X"AE"		--read light intensity	channel 1
);
--start stop condition
signal count:integer range 0 to 1;
signal count_en:std_logic;
--divider
signal Q:std_logic_vector(26 downto 0);
--800K and 400K
signal I2CCLK:std_logic;
signal SCLs:std_logic;
--internal SCL SDA
signal SCL_int,SDA_int:std_logic;
--data to write and read
signal data:std_logic_vector(7 downto 0);
signal data_read:std_logic_vector(7 downto 0);
--data_count to write or read
signal data_enable:std_logic;
signal data_count:integer range 0 to 8;
signal transaction_done:std_logic;
--acknowledge
signal ack_error:std_logic;
signal ack_done:std_logic;
signal shoud_stop:std_logic;
signal re_start_done:std_logic;
--command code done
signal cmd_done:std_logic;
signal data_ready:std_logic;
--TSL2561 datas
signal channel0:std_logic_vector(15 downto 0);	--visible and IR
signal channel1:std_logic_vector(15 downto 0);	--IR
signal ch:integer range 0 to 1;	--channel 01
signal HL:integer range 0 to 1;	--1HIGH 0LOW
--狀態 0關機 1開機
signal TSL_onoff:std_logic;
--1read 0write
signal read_or_write:std_logic;
begin
	divider:--800K
	process(RST,CLK)
	begin
		if RST='0' then
			Q<= (others => '0');
		elsif CLK'event and CLK='1' then
			if Q=62 then
				Q<= (others => '0');
			else
				Q<=Q+1;
			end if;
		end if;
	end process;
	I2CCLK<='1' when Q>31 else '0';
		
	SCL_CLK:--400K
	process(RST,I2CCLK)
	begin
		if RST='0' then
			SCLs<='0';
		elsif rising_edge(I2CCLK) then
			SCLs<=not SCLs;
		end if;
	end process;
	
	
	test_800<=I2CCLK;
	test_400<=SCLs;
	test_count<=data_count;
	act_done<='1' when state=idle else '0';
	with state select
	state_count<=	0 when idle,
						1 when start,
						2 when send_address,
						3 when check_ack,	
						4 when sending_data,
						5 when send_data,
						6 when re_start,
						7 when read_data,
						8 when send_ack,
						9 when stop,
						15 when others;
	
	
	
	counter_controls:
	process(RST,I2CCLK)
	begin
		if RST='0' then
			data_count<=8;
			transaction_done<='0';
			count<=0;
		elsif falling_edge(I2CCLK) then
			if SCLs='1' then
				if count_en='1' then
					if count=1 then
						count<=0;
					else
						count<=count+1;
					end if;
				else
					count<=0;
				end if;
			end if;
			if data_enable='1' then
				if SCLs='0' then
					if data_count=0 then
						transaction_done<='1';
						data_count<=8;
					else
						transaction_done<='0';
						data_count<=data_count-1;
					end if;
				end if;
			else
				transaction_done<='0';
				data_count<=8;
			end if;
		end if;
	end process;
	
	
	I2C_FSM:
	process(RST,CLK)
	begin
		if RST='0' then
			data<="00000000";
			data_read<="00000000";
			state<=idle;
			SCL_int<='1';
			SDA_int<='1';
			TSL_onoff<='1';
			data_enable<='0';
			ack_error<='0';
			ack_done<='0';
			cmd_done<='0';
			read_or_write<='0';
			count_en<='0';
			shoud_stop<='0';
			ch<=0;
			HL<=0;
			data_ready<='0';
			re_start_done<='0';
		elsif rising_edge(CLK) then
			case state is
				when idle=>
					SCL_int<='1';
					SDA_int<='1';
					read_or_write<='0';
					ack_error<='0';
					data_ready<='0';
					data_enable<='0';
					if ena='1' then
						state<=start;
					end if;
				when start=>
					count_en<='1';
					case count is
						when 0=>
							SCL_int<='1';
							SDA_int<='1';
						when 1=>
							SDA_int<='0';
						when others=>
					end case;
					if count=1 then
						count_en<='0';
						state<=send_address;
					end if;
				when send_address=>
					data<="0111001" & read_or_write;
					if SCLs='1' then
						state<=sending_data;
					end if;
				when sending_data=>
					SCL_int<=SCLs;
					if SCLs='0' then
						data_enable<='1';
						SDA_int<=data(data_count);
					elsif transaction_done='1' then
						data_enable<='0';
						state<=check_ack;
					end if;
				when check_ack=>
					SCL_int<=SCLs;
					SDA_int<='1';
					if SCLs='1' then
						if SDA='0' then
							ack_error<=ack_error or '0';
						else
							ack_error<='1';
							shoud_stop<='1';
						end if;
						ack_done<='1';
					elsif ack_done<='1' then
						ack_done<='0';
						if shoud_stop='0' then
							if read_or_write='0' then
								state<=send_data;
							elsif read_or_write='1' then
								if re_start_done='0' then
									re_start_done<='1';
									state<=re_start;
								else
									state<=read_data;
								end if;
							end if;
						else	
							state<=stop;
						end if;
					end if;
					
				when send_data=>
					if data_ready='0' then
						if TSL_onoff<='0' then
							if cmd_done='0' then
								data<=operations(0);
								cmd_done<='1';
								shoud_stop<='0';
							else
								data<=operations(1);
								TSL_onoff<='1';
								cmd_done<='0';
								shoud_stop<='1';
							end if;
							read_or_write<='0';
						else
							data<=operations(2+ch);
							read_or_write<='1';
						end if;
						data_ready<='1';
					elsif SCLs='0' then
						data_ready<='0';
						state<=sending_data;
					end if;
				when re_start=>
					count_en<='1';
					case count is
						when 0=>
							SCL_int<='1';
							SDA_int<='1';
						when 1=>
							SDA_int<='0';
						when others=>
					end case;
					if count=1 then
						count_en<='0';
						state<=send_address;
					end if;
					
				when read_data=>
					SDA_int<='1';
					data_enable<='1';
					SCL_int<=SCLs;
					if SCLs='1' then
						data_read(data_count)<=SDA;
					end if;
					if transaction_done='1' then
						data_enable<='0';
						state<=send_ack;
					end if;
					
				when send_ack=>
					SDA_int<='0';
					SCL_int<=SCLs;
					if ch=0 then
						if HL=0 then
							channel0(7 downto 0)<=data_read;
						elsif HL=0 then
							channel0(15 downto 8)<=data_read;
						end if;
					elsif ch=1 then
						if HL=0 then
							channel1(7 downto 0)<=data_read;
						elsif HL=0 then
							channel1(15 downto 8)<=data_read;
						end if;
					end if;
					
					
					if SCLs='1' then
						ack_done<='1';
					elsif ack_done='1' then
						if HL=1 then
							HL<=0;
							if ch=1 then
								ch<=0;
								shoud_stop<='1';
							else
								ch<=1;
							end if;
						else
							HL<=1;
						end if;
						
						if shoud_stop='0' then
							state<=read_data;
						else
							state<=stop;
						end if;
					end if;
				when stop=>
					count_en<='1';
					SCL_int<=SCLs;
					case count is
						when 0=>
							SDA_int<='0';
						when 1=>
							SDA_int<='1';
						when others=>
					end case;
					
					if count=1 then
						count_en<='0';
						shoud_stop<='0';
						re_start_done<='0';
						state<=idle;
					end if;
			end case;
		end if;
	end process;
	
	SDA<='Z' when SDA_int='1' else '0';
	SCL<='Z' when SCL_int='1' else '0';
	
end TSL;