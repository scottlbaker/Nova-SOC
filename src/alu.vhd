
--========================================================================
-- alu.vhd ::  Nova 16-bit ALU
--
-- (c) Scott L. Baker, Sierra Circuit Design
--========================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

use work.my_types.all;


entity ALU is
    port (
        RBUS      : out std_logic_vector(15 downto 0);  -- Result bus
        CBIT      : out std_logic;                      -- carry status flop
        ZBIT      : out std_logic;                      -- zero  status flop
        ABUS   : in  std_logic_vector(15 downto 0);     -- Src reg
        BBUS   : in  std_logic_vector(15 downto 0);     -- Dst reg
        ALU_OP    : in  ALU_OP_TYPE;                    -- ALU op
        SHIFT_CTL : in  SHIFT_CTL_TYPE;                 -- Shifter op
        CARRY_CTL : in  CARRY_CTL_TYPE;                 -- ALU op
        UPDATE_C  : in  std_logic;                      -- update Carry flag
        UPDATE_Z  : in  std_logic;                      -- update Zero  flag
        RESTORE   : in  std_logic;                      -- restore flags
        SET_C     : in  std_logic;                      -- load CBIT from ACS(0)
        RESET     : in  std_logic;                      -- reset
        FEN       : in  std_logic;                      -- clock enable
        CLK       : in  std_logic                       -- System clock
    );
end ALU;


architecture BEHAVIORAL of ALU is

    --=================================================================
    -- Types, component, and signal definitions
    --=================================================================

    -- internal busses
    signal  AX   : std_logic_vector(16 downto 0);    -- ALU input A
    signal  BX   : std_logic_vector(16 downto 0);    -- ALU input B
    signal  SUM  : std_logic_vector(16 downto 0);    -- ALU output
    signal  SHF  : std_logic_vector(15 downto 0);    -- shifter output

    -- internal carries
    signal  CIN      : std_logic;
    signal  COUT     : std_logic;
    signal  C16      : std_logic;
    signal  ZOUT     : std_logic;
    signal  ALU_COUT : std_logic;
    signal  SHF_COUT : std_logic;
    signal  CBIT_FF  : std_logic;
    signal  ZBIT_FF  : std_logic;
    signal  OLD_CBIT : std_logic;
    signal  OLD_ZBIT : std_logic;

begin

    --================================================================
    -- Start of the behavioral description
    --================================================================

    --========================
    -- ALU Opcode Decoding
    --========================
    ALU_OPCODE_DECODING:
    process(ALU_OP, ABUS, BBUS, C16)
    begin

        -- default values
        AX   <= ABUS(15) & ABUS;
        BX   <= (others => '0');
        CIN  <= '0';
        COUT <= '0';

        case ALU_OP is

            when NEG =>             -- 2's complement
                AX <= not (ABUS(15) & ABUS);
                CIN  <= '1';
                COUT <= C16;

            when COM =>             -- 1's complement
                AX <= not (ABUS(15) & ABUS);

            when INC =>             -- Increment
                CIN  <= '1';
                COUT <= C16;

            when DEC =>             -- Decrement
                BX <= (others => '1');
                COUT <= C16;

            when ADC =>             -- Add complement
                AX <= not (ABUS(15) & ABUS);
                BX <= BBUS(15) & BBUS;
                COUT <= C16;

            when SUB =>             -- Subtract
                AX <= not (ABUS(15) & ABUS);
                BX <= BBUS(15) & BBUS;
                CIN  <= '1';
                COUT <= C16;

            when ADD =>             -- Add
                BX <= BBUS(15) & BBUS;
                COUT <= C16;

            when ANA =>             -- Logical And
                BX <= BBUS(15) & BBUS;

            when others =>          -- Transfer A

        end case;

    end process;


    --========================
    -- The ALU
    --========================
    ALU:
    process(AX, BX, CIN, ALU_OP)
    begin

        SUM <= AX + BX + CIN;

        if (ALU_OP = ANA) then
            SUM <= AX and BX;
        end if;

    end process;

    C16  <= SUM(16) xor AX(16) xor BX(16);

    --========================
    -- The ALU carry out
    --========================
    ALU_CARRY_CONTROL:
    process(CARRY_CTL, COUT, CBIT_FF)
    begin
        case CARRY_CTL is
            when CLEAR =>
                ALU_COUT <= COUT;
            when SET =>
                ALU_COUT <= not COUT;
            when INVERT =>
                ALU_COUT <= CBIT_FF xnor COUT;
            when others =>
                ALU_COUT <= CBIT_FF xor COUT;
        end case;
    end process;


    --========================
    -- ALU output shifter
    --========================
    SHIFT_OPCODE_DECODING:
    process(SHIFT_CTL, SUM, ALU_COUT)
    begin

        case SHIFT_CTL is

            when LEFT  =>          -- Rotate left
                SHF(15 downto 1) <= SUM(14 downto 0);
                SHF(0)   <= ALU_COUT;
                SHF_COUT <= SUM(15);

            when RIGHT =>          -- Rotate right
                SHF(14 downto 0) <= SUM(15 downto 1);
                SHF(15)  <= ALU_COUT;
                SHF_COUT <= SUM(0);

            when SWAP  =>          -- Swap bytes
                SHF(15 downto 8) <= SUM( 7 downto 0);
                SHF( 7 downto 0) <= SUM(15 downto 8);
                SHF_COUT <= ALU_COUT;

            when others =>          -- No shift
                SHF      <= SUM(15 downto 0);
                SHF_COUT <= ALU_COUT;

        end case;

    end process;

    RBUS <= SHF;

    ZOUT <= not (SHF(15) or SHF(14) or SHF(13) or SHF(12) or
                 SHF(11) or SHF(10) or SHF( 9) or SHF( 8) or
                 SHF( 7) or SHF( 6) or SHF( 5) or SHF( 4) or
                 SHF( 3) or SHF( 2) or SHF( 1) or SHF( 0));

    --================================================================
    -- carry status flip-flop
    --================================================================
    CARRY_STATUS_FLOP:
    process(RESET, CLK)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (UPDATE_C = '1') then
                CBIT_FF  <= SHF_COUT;
                OLD_CBIT <= CBIT_FF;
            end if;
            if (RESTORE = '1') then
                CBIT_FF <= OLD_CBIT;
            end if;
            if (SET_C = '1') then
                CBIT_FF <= ABUS(15);
            end if;
        end if;
        end if;
        -- reset state
        if (RESET = '1') then
            CBIT_FF  <= '0';
            OLD_CBIT <= '0';
        end if;
    end process;


    --================================================================
    -- zero status flip-flop
    --================================================================
    ZERO_STATUS_FLOP:
    process(RESET, CLK)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (UPDATE_Z = '1') then
                ZBIT_FF <= ZOUT;
                OLD_ZBIT <= ZBIT_FF;
            end if;
            if (RESTORE = '1') then
                ZBIT_FF <= OLD_ZBIT;
            end if;
        end if;
        end if;
        -- reset state
        if (RESET = '1') then
            ZBIT_FF  <= '0';
            OLD_ZBIT <= '0';
        end if;
    end process;

    CBIT <= CBIT_FF;
    ZBIT <= ZBIT_FF;

end BEHAVIORAL;
