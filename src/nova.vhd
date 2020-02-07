
--======================================================================
-- nova.vhd ::  Nova instruction-set compatible microprocessor
--======================================================================
--
-- The Nova was an elegantly simple 16-bit minicompter designed by
-- Edson Decastro, the founder of Data General, Inc.
-- The orignial Nova-1200 was implemented in MSI TTL on a single 
-- 15"x15" circuit board.  The Nova 1200 was followed by several more
-- Nova processors including the Nova-3 and Nova-4, all of which shared
-- an upwardly-compatible instruction set (later models had additional
-- instructions. The NOVA had four 16-bit accumulators, as well as a
-- program counter, stack pointer, and stack frame pointer registers
-- (the last two were only on later Nova models).
--
-- (c) Scott L. Baker, Sierra Circuit Design
--======================================================================

library IEEE;
use IEEE.std_logic_1164.all;

use work.my_types.all;


entity IP_NOVA is
    port (
          ADDR_15    : out std_logic_vector(15 downto 1);  -- for debug only
          ADDR_OUT   : out std_logic_vector(15 downto 0);
          DATA_IN    : in  std_logic_vector(15 downto 0);
          DATA_OUT   : out std_logic_vector(15 downto 0);
          DEVCODE    : out std_logic_vector( 5 downto 0);  -- I/O device

          R_W        : out std_logic;   -- Mem 1==read 0==write
          IORW       : out std_logic;   -- I/O 1==read 0==write
          BYTE       : out std_logic;   -- Byte memory operation
          IOM        : out std_logic;   -- 1==I/O  0==memory
          SYNC       : out std_logic;   -- Opcode fetch status

          IRQ        : in  std_logic;   -- Interrupt Request (active-low)
          PWR_GOOD   : in  std_logic;   -- Power good
          RDY        : in  std_logic;   -- Ready input
          RESET      : in  std_logic;   -- Reset input (active-low)
          FEN        : in  std_logic;   -- clock enable
          CLK        : in  std_logic;   -- System Clock

          DBUG7      : out std_logic;   -- for debug
          DBUG6      : out std_logic;   -- for debug
          DBUG5      : out std_logic;   -- for debug
          DBUG4      : out std_logic;   -- for debug
          DBUG3      : out std_logic;   -- for debug
          DBUG2      : out std_logic;   -- for debug
          DBUG1      : out std_logic    -- for debug
         );
end IP_NOVA;


architecture BEHAVIORAL of IP_NOVA is

    --=================================================================
    -- Types, component, and signal definitions
    --=================================================================

    --=================================================================
    -- Register operations
    --=================================================================
    type  REG_OP_TYPE is (
              LDR,      -- load from ALU result bus
              HOLD      -- hold
          );

    --=================================================================
    -- Scratch-register operations
    --=================================================================
    type  SR1_OP_TYPE is (
              LDR,      -- load from ALU result bus
              LD_DB,    -- load from data bus
              HOLD      -- hold
          );

    --=================================================================
    -- Program-Counter operations
    --=================================================================
    type  PC_OP_TYPE is (
              LDR,      -- load from ALU result bus
              LD_SX,    -- load from address adder
              LD_EA,    -- load from EA
              HOLD      -- hold
          );

    --=================================================================
    -- Stack Pointer operations
    --=================================================================
    type  SP_OP_TYPE is (
              LDR,      -- load from ALU result bus
              LD_FP,    -- load from FP
              LD_SX,    -- load from address adder
              HOLD      -- hold
          );

    --=================================================================
    -- Frame Pointer operations
    --=================================================================
    type  FP_OP_TYPE is (
              LDR,      -- load from ALU result bus
              LD_SP,    -- load from SP
              HOLD      -- hold
          );

    --=================================================================
    -- Effective address register operations
    --=================================================================
    type  EA_OP_TYPE is (
              LD_SX,    -- load from address adder
              LD_DB,    -- load from data bus
              LD_SR1,   -- load from scratch register
              LD_ZP,    -- load zero-page address
              HOLD      -- hold
          );

    --=================================================================
    -- Address Adder B-mux Selects
    --=================================================================
    type  SX_BSEL_TYPE is (
              SEL_PC,
              SEL_AC2,
              SEL_AC3,
              SEL_EA,
              SEL_SP
          );

    --=================================================================
    -- Microcode States
    --=================================================================
    type  UCODE_STATE_TYPE is (
              AUTO_DEC1,
              AUTO_INC1,
              CHECK_SKIP,
              EA_VALID,
              FETCH_OPCODE,
              GOT_OPCODE,
              HALT_1,
              JSR_1,
              PSHA_1,
              STORE_SR1,
              STORE_EA,
              RET_1,
              RET_2,
              RET_3,
              RET_4,
              RET_5,
              SAV_1,
              SAV_2,
              SAV_3,
              SAV_4,
              SAV_5,
              SAV_6,
              RST_1,
              UII_1
          );

    signal STATE       : UCODE_STATE_TYPE;
    signal NEXT_STATE  : UCODE_STATE_TYPE;

    signal AC0_OPCODE  : REG_OP_TYPE;     -- Accumulator 0 micro op
    signal AC1_OPCODE  : REG_OP_TYPE;     -- Accumulator 1 micro op
    signal AC2_OPCODE  : REG_OP_TYPE;     -- Accumulator 2 micro op
    signal AC3_OPCODE  : REG_OP_TYPE;     -- Accumulator 3 micro op
    signal SR1_OPCODE  : SR1_OP_TYPE;     -- Scratch Reg 1 micro op

    signal PC_OPCODE   : PC_OP_TYPE;      -- Program-counter micro op
    signal EA_OPCODE   : EA_OP_TYPE;      -- EA register   micro op
    signal SP_OPCODE   : SP_OP_TYPE;      -- Stack pointer micro op
    signal FP_OPCODE   : FP_OP_TYPE;      -- Frame pointer micro op
    signal ALX_OPCODE  : ALU_OP_TYPE;     -- ALU micro-op (from decoder)
    signal ALY_OPCODE  : ALU_OP_TYPE;     -- ALU micro-op (auxilary)
    signal ALU_OPCODE  : ALU_OP_TYPE;     -- ALU micro-op
    signal USE_ALU     : std_logic;       -- select ALU micro-op
    signal SX_OPCODE   : SX_OP_TYPE;      -- Address adder micro op
    signal SX_BSEL     : SX_BSEL_TYPE;    -- Address adder operand select

    signal FORMAT      : OP_FORMAT_TYPE;  -- Opcode format
    signal ADDR_MODE   : ADDR_MODE_TYPE;  -- Address mode
    signal IDX_CTL     : IDX_CTL_TYPE;    -- Index control
    signal CARRY_CTL   : CARRY_CTL_TYPE;  -- Carry control
    signal SHIFT_CTL   : SHIFT_CTL_TYPE;  -- Shift control
    signal SHIFT_DEC   : SHIFT_CTL_TYPE;  -- Shift control
    signal SKIP_CTL    : SKIP_CTL_TYPE;   -- Shift control
    signal FLOW_CTL    : FLOW_CTL_TYPE;   -- Flow control
    signal XFER_CTL    : XFER_CTL_TYPE;   -- Transfer control
    signal IOU_CTL     : IOU_CTL_TYPE;    -- I/O control
    signal EXT_OP      : EXT_OP_TYPE;     -- Extended opcode
    signal NO_LOAD     : std_logic;       -- Load control
    signal IND_CTL     : std_logic;       -- Indirect bit from decoder
    signal INDIRECT    : std_logic;       -- Indirect level flop
    signal CLR_IND     : std_logic;       -- clear Indirect flop
    signal PC_TO_AC3   : std_logic;       -- save PC for JSR

    signal ASX_SEL     : std_logic_vector( 1 downto 0);  -- from decoder
    signal ASY_SEL     : std_logic_vector( 1 downto 0);  -- auxilary select
    signal ACS_SEL     : std_logic_vector( 1 downto 0);  -- source  select
    signal USE_ACS     : std_logic;                      -- use aux select
    signal ACS_FP      : std_logic;                      -- select FP
    signal ACS_SP      : std_logic;                      -- select SP
    signal ACS_SR1     : std_logic;                      -- select SR1
    signal ACS_DIN     : std_logic;                      -- select data_in
    signal LDB_OP      : std_logic;                      -- load  byte
    signal STB_OP      : std_logic;                      -- store byte

    signal BMUX_SEL    : std_logic_vector( 1 downto 0);  -- from decoder
    signal DEST_SEL    : std_logic_vector( 1 downto 0);  -- dest reg select
    signal ADY_SEL     : std_logic_vector( 1 downto 0);  -- auxilary select
    signal USE_ACD     : std_logic;                      -- use aux select

    signal AMUX        : std_logic_vector(15 downto 0);  -- source mux
    signal BMUX        : std_logic_vector(15 downto 0);  -- dest   mux

    -- Internal busses
    signal RBUS        : std_logic_vector(15 downto 0);  -- result bus
    signal SX          : std_logic_vector(15 downto 0);  -- address bus S
    signal BX          : std_logic_vector(15 downto 0);  -- address bus B
    signal ADDR_OX     : std_logic_vector(15 downto 0);  -- Internal addr bus

    -- Architectural registers
    signal AC0         : std_logic_vector(15 downto 0);  -- accumulator 0
    signal AC1         : std_logic_vector(15 downto 0);  -- accumulator 1
    signal AC2         : std_logic_vector(15 downto 0);  -- accumulator 2
    signal AC3         : std_logic_vector(15 downto 0);  -- accumulator 3

    signal SP          : std_logic_vector(15 downto 0);  -- stack pointer
    signal FP          : std_logic_vector(15 downto 0);  -- frame pointer
    signal PC          : std_logic_vector(15 downto 0);  -- program counter
    signal EA          : std_logic_vector(15 downto 0);  -- effective address

    -- Scratch registers
    signal SR1         : std_logic_vector(15 downto 0);  -- scratch reg 1
    signal OPREG       : std_logic_vector(15 downto 0);  -- opcode reg

    -- Status flags
    signal IRQ_FF      : std_logic;  -- IRQ flip-flop
    signal INTEN       : std_logic;  -- Interrupt Enable flip-flop
    signal CBIT        : std_logic;  -- carry flag
    signal ZBIT        : std_logic;  -- zero  flag
    signal LOAD_STAT   : std_logic;  -- Load I/O busy/done flags
    signal BUSY        : std_logic;  -- I/O busy flag
    signal DONE        : std_logic;  -- I/O done flag

    -- Status flag update
    signal UPDATE_C    : std_logic;  -- update carry flag
    signal UPDATE_Z    : std_logic;  -- update zero  flag
    signal RESTORE     : std_logic;  -- Restore flags
    signal SET_I       : std_logic;  -- set   Interrupt Enable flag
    signal CLR_I       : std_logic;  -- clear Interrupt Enable flag
    signal SET_C       : std_logic;  -- load CBIT

    -- Misc
    signal MY_RESET    : std_logic;  -- active high reset
    signal MMWRITE     : std_logic;  -- Mem Write control
    signal IOWRITE     : std_logic;  -- I/O Write control
    signal ACC_LOAD    : std_logic;  -- accumulator load
    signal SKIP_COND   : std_logic;  -- skip condition


    --================================================================
    -- Constant definition section
    --================================================================

    -- Interrupt vector = $0002
    constant INT_VEC  : std_logic_vector(15 downto 0) := "0000000000000010";

    -- Misc
    constant END_OF_WAIT : std_logic_vector(8 downto 0) := "100000000";

    --================================================================
    -- Component definition section
    --================================================================

    --==========================
    -- instruction decoder
    --==========================
    component DECODE
    port (

        -- opcode input
        DECODE_IN  : in  std_logic_vector(15 downto 0);

        -- opcode classes
        FORMAT     : out OP_FORMAT_TYPE;                -- opcode format
        ADDR_MODE  : out ADDR_MODE_TYPE;                -- address mode

        -- ALU opcode fields
        SRC_SEL    : out std_logic_vector(1 downto 0);  -- Source register
        DST_SEL    : out std_logic_vector(1 downto 0);  -- Destination reg
        ALU_OP     : out ALU_OP_TYPE;                   -- ALU micro-op
        SHIFT_CTL  : out SHIFT_CTL_TYPE;                -- Shifter control
        CARRY_CTL  : out CARRY_CTL_TYPE;                -- Carry control
        NO_LOAD    : out std_logic;                     -- Load control
        SKIP_CTL   : out SKIP_CTL_TYPE;                 -- Skip control

        -- Memory xfer opcode fields
        FLOW_CTL   : out FLOW_CTL_TYPE;                 -- Flow control
        IND_CTL    : out std_logic;                     -- Indirect control
        IDX_CTL    : out IDX_CTL_TYPE;                  -- Index control

        -- I/O opcode fields
        XFER_CTL   : out XFER_CTL_TYPE;                 -- Transfer control
        IOU_CTL    : out IOU_CTL_TYPE;                  -- I/O device control

        EXT_OP     : out EXT_OP_TYPE                    -- extended opcode
       );
    end component;


    --==========================
    -- 16-bit ALU 
    --==========================
    component ALU
    port (
        RBUS      : out std_logic_vector(15 downto 0);  -- Result bus
        CBIT      : out std_logic;                      -- carry status
        ZBIT      : out std_logic;                      -- zero status
        ABUS      : in  std_logic_vector(15 downto 0);  -- Src reg
        BBUS      : in  std_logic_vector(15 downto 0);  -- Dst reg
        ALU_OP    : in  ALU_OP_TYPE;                    -- ALU op
        SHIFT_CTL : in  SHIFT_CTL_TYPE;                 -- Shifter op
        CARRY_CTL : in  CARRY_CTL_TYPE;                 -- ALU op
        UPDATE_C  : in  std_logic;                      -- update carry flag
        UPDATE_Z  : in  std_logic;                      -- update zero  flag
        RESTORE   : in  std_logic;                      -- restore flags
        SET_C     : in  std_logic;                      -- load CBIT
        RESET     : in  std_logic;                      -- reset
        FEN       : in  std_logic;                      -- clock enable
        CLK       : in  std_logic                       -- System clock
       );
    end component;


    --==========================
    -- 16-bit Address Adder
    --==========================
    component ADDR
    port (
        SX     : out std_logic_vector(15 downto 0);   -- result bus
        BX     : in  std_logic_vector(15 downto 0);   -- operand bus
        DISP   : in  std_logic_vector( 7 downto 0);   -- displacement
        OP     : in  SX_OP_TYPE                       -- micro op
       );
    end component;


    --================================================================
    -- End of types, component, and signal definition section
    --================================================================

begin

    --================================================================
    -- Start of the behavioral description
    --================================================================

    MY_RESET <= not RESET;

    --================================================================
    -- Microcode state machine
    --================================================================
    MICROCODE_STATE_MACHINE:
    process(CLK)
    begin
        if (CLK = '0' and CLK'event) then
            if ((FEN = '1') and (RDY = '1')) then
                STATE <= NEXT_STATE;
                -- reset state
                if (MY_RESET = '1') then
                    STATE <= RST_1;
                end if;
            end if;
        end if;
    end process;


    --================================================================
    -- Source register mux
    --================================================================
    SRC_REGISTER_MUX:
    process(ACS_SEL, AC0, AC1, AC2, AC3, USE_ACS, CBIT,
            ACS_DIN, DATA_IN, ACS_FP, FP, ACS_SP, SP, ACS_SR1, SR1,
            LDB_OP, BMUX)
    begin
        case ACS_SEL is
            when "00" =>
                AMUX <= AC0;
            when "01" =>
                AMUX <= AC1;
            when "10" =>
                AMUX <= AC2;
            when others =>
                AMUX <= AC3;
                -- special case for SAV opcode
                if (USE_ACS = '1') then
                   AMUX <= CBIT & AC3(14 downto 0);
                end if;
        end case;

        if (ACS_FP = '1') then
            AMUX <= '0'  & FP(15 downto 1);
        end if;
        if (ACS_SP = '1') then
            AMUX <= '0'  & SP(15 downto 1);
        end if;
        if (ACS_SR1 = '1') then
            AMUX <= SR1;
        end if;
        if (ACS_DIN = '1') then
            AMUX <= DATA_IN;
        end if;

        if (LDB_OP = '1') then
            -- check bit 0 of the byte address
            if (BMUX(0) = '0') then
                AMUX <= "00000000" & DATA_IN( 7 downto 0);
            else
                AMUX <= "00000000" & DATA_IN(15 downto 8);
            end if;
        end if;

    end process;


    --================================================================
    -- Destination mux
    --================================================================
    DST_REGISTER_MUX:
    process(BMUX_SEL, AC0, AC1, AC2, AC3)
    begin

        case BMUX_SEL is
            when "00" =>
                BMUX <= AC0;
            when "01" =>
                BMUX <= AC1;
            when "10" =>
                BMUX <= AC2;
            when others =>
                BMUX <= AC3;
        end case;

    end process;


    --================================================================
    -- Select Accumulator to load
    --================================================================
    REGISTER_LOAD_SELECT:
    process(DEST_SEL, ACC_LOAD)
    begin
        AC0_OPCODE <= HOLD;
        AC1_OPCODE <= HOLD;
        AC2_OPCODE <= HOLD;
        AC3_OPCODE <= HOLD;

        if (ACC_LOAD = '1') then
            case DEST_SEL is
                when "00" =>
                    AC0_OPCODE <= LDR;
                when "01" =>
                    AC1_OPCODE <= LDR;
                when "10" =>
                    AC2_OPCODE <= LDR;
                when others =>
                    AC3_OPCODE <= LDR;
            end case;
        end if;
    end process;


    --==================================================
    -- Address Adder Mux B
    --==================================================
    ADDRESS_ADDER_MUX_B:
    process(SX_BSEL, AC2, AC3, EA, SP, PC)
    begin

        case SX_BSEL IS
            when SEL_AC2 =>
                BX <= AC2(14 downto 0) & '0';
            when SEL_AC3 =>
                BX <= AC3(14 downto 0) & '0';
            when SEL_EA =>
                BX <= EA;
            when SEL_SP =>
                BX <= SP;
            when others =>
                BX <= PC;
        end case;
    end process;


    --================================================================
    -- Debug signals
    --================================================================
    DBUG1  <= '0';
    DBUG2  <= '0';
    DBUG3  <= '0';
    DBUG4  <= '0';
    DBUG5  <= '0';
    DBUG6  <= '0';
    DBUG7  <= '0';

    ADDR_OUT <= ADDR_OX;
    ADDR_15  <= ADDR_OX(15 downto 1);  -- for simulation display
    DEVCODE  <= OPREG(5 downto 0);     -- I/O device code

    --================================================================
    -- Register IRQ (active-low) inputs
    --================================================================
    INTERRUPT_STATUS_REGISTERS:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            -- only set the IRQ flip-flop if enabled
            IRQ_FF <= not (IRQ or not INTEN);
            -- Interrupt Enable flag
            if (SET_I = '1') then
                INTEN <= '1';
            end if;
            if (CLR_I = '1') then
                INTEN <= '0';
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            IRQ_FF <= '0';
            INTEN  <= '0';
        end if;
    end process;


    --================================================================
    -- I/O Busy/Done Status
    --================================================================
    BUSY_DONE_STATUS:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (LOAD_STAT = '1') then
                BUSY <= DATA_IN(15);
                DONE <= DATA_IN(14);
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            BUSY <= '0';
            DONE <= '0';
        end if;
    end process;


    --================================================================
    -- Indirect status
    --================================================================
    INDIRECT_STATUS:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (STATE = GOT_OPCODE) then
                INDIRECT <= IND_CTL;
            end if;
            if (CLR_IND = '1') then
                INDIRECT <= '0';
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            INDIRECT <= '1';   -- jmp @3
        end if;
    end process;


    --================================================================
    -- Opcode Register
    --================================================================
    OPCODE_REGISTER:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (STATE = FETCH_OPCODE) then
                OPREG <= DATA_IN;
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            OPREG <= x"0403";  -- jmp @3
        end if;
    end process;


    --================================================================
    -- Micro-operation and next-state generation
    --================================================================
    MICRO_OP_AND_NEXT_STATE_GENERATION:
    process(ADDR_MODE, STATE, RBUS, PC, EA, SP, SR1, IRQ_FF, OPREG,
            EXT_OP, IOU_CTL, XFER_CTL, SKIP_CTL, FLOW_CTL, IDX_CTL,
            BMUX, SKIP_COND, FORMAT, INDIRECT, DATA_IN,
            NO_LOAD, SHIFT_DEC)
    begin

        -- default micro-ops
        PC_OPCODE  <= HOLD;
        SX_OPCODE  <= INC1;
        SX_BSEL    <= SEL_PC;
        EA_OPCODE  <= HOLD;
        SP_OPCODE  <= HOLD;
        FP_OPCODE  <= HOLD;
        SR1_OPCODE <= HOLD;

        MMWRITE    <= '0';    -- 0==read 1==write
        IOWRITE    <= '0';    -- 0==read 1==write
        BYTE       <= '0';    -- 1==byte 0==word
        IOM        <= '0';    -- 1==I/O  0==memory
        ACC_LOAD   <= '0';
        ACS_FP     <= '0';
        ACS_SP     <= '0';
        ACS_SR1    <= '0';
        ACS_DIN    <= '0';
        DATA_OUT   <= RBUS;
        NEXT_STATE <= FETCH_OPCODE;
        SHIFT_CTL  <= SHIFT_DEC;
        ADDR_OX    <= PC;

        USE_ALU    <= '0';    -- use aux ALU control
        USE_ACS    <= '0';    -- use aux source register select
        USE_ACD    <= '0';    -- use aux dest   register select
        ALY_OPCODE <= INC;    -- default auxillary ALU op
        ASY_SEL    <= "00";   -- default auxillary source select
        ADY_SEL    <= "00";   -- default auxillary source select

        UPDATE_C   <= '0';    -- update carry flag
        UPDATE_Z   <= '0';    -- update zero  flag
        RESTORE    <= '0';    -- restore ALU flags
        SET_I      <= '0';    -- set   Interrupt Enable flag
        CLR_I      <= '0';    -- clear Interrupt Enable flag
        SET_C      <= '0';    -- load CBIT
        CLR_IND    <= '0';    -- clear indirect flop
        LOAD_STAT  <= '0';    -- load I/O busy/done status
        PC_TO_AC3  <= '0';    -- save PC for JSR
        LDB_OP     <= '0';    -- load  byte operation
        STB_OP     <= '0';    -- store byte operation

        case STATE is

        --============================================
        -- Reset startup sequence
        --============================================
        when RST_1 =>
            -- Stay here until reset is de-bounced
            PC_OPCODE  <= HOLD;
            NEXT_STATE <= GOT_OPCODE;


        --============================================
        -- Fetch Opcode State
        --============================================
        when FETCH_OPCODE =>

            -- Check for IRQ
            if (IRQ_FF = '1') then
                CLR_I <= '1';  -- Disable further interrupts
                ADDR_OX <= "0000000000000010";
                USE_ALU <= '1';
                ALY_OPCODE <= TA;
                PC_OPCODE  <= LDR;  -- load vector
                NEXT_STATE <= FETCH_OPCODE;
            else
                -- Fetch the opcode
                NEXT_STATE <= GOT_OPCODE;
            end if;

        --============================================
        -- Opcode Latch contains an opcode
        --============================================
        when GOT_OPCODE =>

            PC_OPCODE <= LD_SX;
            case ADDR_MODE is

                --=================================
                -- Calculate Effective Address
                --=================================
                when ADM_EA =>

                    PC_OPCODE <= HOLD;

                    case IDX_CTL is
                        when REL  =>    -- PC relative
                            SX_OPCODE <= REL;
                            SX_BSEL   <= SEL_PC;
                            EA_OPCODE <= LD_SX;
                        when IDX2 =>    -- AC2 indexed
                            SX_OPCODE <= REL;
                            SX_BSEL   <= SEL_AC2;
                            EA_OPCODE <= LD_SX;
                        when IDX3 =>    -- AC3 indexed
                            SX_OPCODE <= REL;
                            SX_BSEL   <= SEL_AC3;
                            EA_OPCODE <= LD_SX;
                        when others =>  -- zero page
                            EA_OPCODE <= LD_ZP;
                    end case;
                    NEXT_STATE <= EA_VALID;


                --=================================
                -- Implied Addressing Mode
                --=================================
                when others =>

                    case FORMAT is

                        when ALU_FORMAT =>

                            UPDATE_C <= '1';
                            UPDATE_Z <= '1';
                            -- load control
                            ACC_LOAD <= not NO_LOAD;
                            case SKIP_CTL is
                                when SKP =>     -- skip always
                                    SX_OPCODE <= INC2;
                                    SX_BSEL   <= SEL_PC;
                                    if (NO_LOAD = '1') then
                                        UPDATE_C <= '0';
                                        UPDATE_Z <= '0';
                                    end if;
                                    NEXT_STATE <= FETCH_OPCODE;
                                when NOP =>     -- skip never
                                    NEXT_STATE <= FETCH_OPCODE;
                                when others =>  -- evaluate skip cond
                                    NEXT_STATE <= CHECK_SKIP;
                            end case;

                        when IOU_FORMAT =>

                            IOM <= '1';

                            -- check for device 0x3f special cases
                            if (OPREG(5 downto 0) = "111111") then

                                -- Interrupt Enable flag control
                                case IOU_CTL is
                                    when SBCD =>  -- set
                                        SET_I <= '1';
                                    when CBCD =>  -- clear
                                        CLR_I <= '1';
                                    when others =>
                                end case;

                                case XFER_CTL is

                                    when DIA =>  -- read switches
                                        ACC_LOAD <= '1';

                                    when DOA =>  -- nop

                                    when DIB =>  -- interrupt acknowledge
                                        ACC_LOAD <= '1';

                                    when DOB =>  -- mask out

                                    when DIC =>  -- I/O reset

                                    when DOC =>  -- Halt
                                        PC_OPCODE <= HOLD;
                                        NEXT_STATE <= HALT_1;

                                    when SKP =>  -- CPU skip
                                        NEXT_STATE <= CHECK_SKIP;

                                    when others =>

                                end case;

                            else

                                case XFER_CTL is

                                    when NOP =>  -- special case ops

                                    when DIA =>  -- data in from buffer A
                                        ACC_LOAD <= '1';
                                        ACS_DIN <= '1';

                                    when DOA =>  -- data out  to buffer A
                                        IOWRITE <= '1';

                                    when DIB =>  -- data in from buffer B
                                        ACC_LOAD <= '1';
                                        ACS_DIN <= '1';

                                    when DOB =>  -- data out  to buffer B
                                        IOWRITE <= '1';

                                    when DIC =>  -- data in from buffer C
                                        ACC_LOAD <= '1';
                                        ACS_DIN <= '1';

                                    when DOC =>  -- data out  to buffer C
                                        IOWRITE <= '1';

                                    when SKP =>  -- skip on I/O condition
                                        LOAD_STAT  <= '1';
                                        NEXT_STATE <= CHECK_SKIP;

                                    when others =>
                                end case;
                            end if;


                        when EXT_FORMAT =>

                            case EXT_OP is

                                when LDB  =>  -- load  byte
                                    LDB_OP   <= '1';
                                    ADDR_OX  <= BMUX;
                                    ACC_LOAD <= '1';

                                when STB  =>  -- store byte
                                    STB_OP  <= '1';
                                    MMWRITE <= '1';
                                    BYTE    <= '1';
                                    ADDR_OX <= BMUX;
                                    if (BMUX(0) = '1') then
                                        SHIFT_CTL <= SWAP;
                                    end if;

                                when MTFP =>  -- move to frame pointer
                                    FP_OPCODE <= LDR;

                                when MFFP =>  -- move from frame pointer
                                    ACS_FP   <= '1';
                                    ACC_LOAD <= '1';

                                when MTSP =>  -- move to stack pointer
                                    SP_OPCODE <= LDR;

                                when MFSP =>  -- move from stack pointer
                                    ACS_SP   <= '1';
                                    ACC_LOAD <= '1';

                                when PSHA =>  -- push accumulator
                                    -- pre-inc the stack pointer
                                    SX_BSEL    <= SEL_SP;
                                    SX_OPCODE  <= INC1;
                                    SP_OPCODE  <= LD_SX;
                                    NEXT_STATE <= PSHA_1;

                                when POPA =>  -- pop accumulator
                                    ACS_DIN    <= '1';
                                    ACC_LOAD   <= '1';
                                    ADDR_OX    <= SP;
                                    -- decrement the stack pointer
                                    SX_BSEL    <= SEL_SP;
                                    SX_OPCODE  <= DEC1;
                                    SP_OPCODE  <= LD_SX;
                                    NEXT_STATE <= FETCH_OPCODE;

                                when SAV  =>  -- save registers
                                    NEXT_STATE <= SAV_1;

                                when RET  =>  -- return from subroutine
                                    ACS_FP <= '1';
                                    SP_OPCODE  <= LD_FP;  -- copy FP to SP
                                    NEXT_STATE <= RET_1;

                                when others =>
                            end case;

                        -- unimplemented
                        when others =>
                            NEXT_STATE <= UII_1;

                    end case;  -- end of FORMAT case

            end case;  -- end of ADDR_MODE case

            if (FORMAT = UII_FORMAT) then
                NEXT_STATE <= UII_1;
            end if;


        --=====================================================
        -- At this point we have the 16-bit absolute address
        -- stored in the EA register.
        --=====================================================
        when EA_VALID =>

            PC_OPCODE  <= HOLD;
            NEXT_STATE <= FETCH_OPCODE;
            -- Check for indirection
            ADDR_OX <= EA;
            if (INDIRECT = '1') then
                NEXT_STATE <= EA_VALID;
                EA_OPCODE  <= LD_DB;  -- load vector
                -- check for levels of indirection
                if (DATA_IN(15) = '0') then
                    -- Indirection is complete
                    CLR_IND <= '1';   -- clear indirect flop
                end if;
                -- check for Auto-Inc/Auto-Dec
                if (EA(15 downto 6) = "0000000000") then
                    if (EA( 5 downto 4) = "10") then
                        EA_OPCODE  <= HOLD;
                        SR1_OPCODE <= LD_DB;
                        NEXT_STATE <= AUTO_INC1;
                    end if;
                    if (EA( 5 downto 4) = "11") then
                        EA_OPCODE  <= HOLD;
                        SR1_OPCODE <= LD_DB;
                        NEXT_STATE <= AUTO_DEC1;
                    end if;
                end if;
            else
                PC_OPCODE <= LD_SX;
                case FORMAT is
                    -- load the selected accumulator
                    when LDA_FORMAT =>
                        ACS_DIN  <= '1';
                        ACC_LOAD <= '1';
                    -- store the selected accumulator
                    when STA_FORMAT =>
                        MMWRITE <= '1';
                    -- Program flow control
                    when MEM_FORMAT =>
                        case FLOW_CTL is
                            -- jump to address
                            when JMP =>
                                PC_OPCODE  <= LD_EA;
                            -- jump to subroutine
                            when JSR =>
                                PC_OPCODE <= LD_SX;
                                NEXT_STATE <= JSR_1;
                            -- incr and skip if zero
                            when ISZ =>
                                ACS_DIN <= '1';
                                SR1_OPCODE <= LDR;
                                UPDATE_Z   <= '1';
                                NEXT_STATE <= STORE_SR1;
                            -- decr and skip if zero
                            when DSZ =>
                                ACS_DIN <= '1';
                                SR1_OPCODE <= LDR;
                                UPDATE_Z   <= '1';
                                NEXT_STATE <= STORE_SR1;
                            -- unimplemented
                            when others =>
                                NEXT_STATE <= UII_1;

                        end case;

                    -- unimplemented
                    when others =>
                        NEXT_STATE <= UII_1;

                end case;
            end if;


        --=====================================================
        -- Complete the ISZ/DSZ instructions
        --=====================================================
        when STORE_SR1 =>
            -- store the scratch register
            ADDR_OX   <= EA;
            DATA_OUT  <= SR1;
            PC_OPCODE <= HOLD;
            MMWRITE   <= '1';
            NEXT_STATE <= CHECK_SKIP;


        --=====================================================
        -- Complete AutoInc and AutoDec Indirection
        --=====================================================
        when AUTO_INC1 =>
            ACS_SR1    <= '1';
            USE_ALU    <= '1';
            ALY_OPCODE <= INC;
            SR1_OPCODE <= LDR;
            NEXT_STATE <= STORE_EA;

        when AUTO_DEC1 =>
            ACS_SR1    <= '1';
            USE_ALU    <= '1';
            ALY_OPCODE <= DEC;
            SR1_OPCODE <= LDR;
            NEXT_STATE <= STORE_EA;

        when STORE_EA =>
            -- store the scratch register
            ADDR_OX   <= EA;
            DATA_OUT  <= SR1;
            EA_OPCODE <= LD_SR1;
            MMWRITE   <= '1';
            NEXT_STATE <= EA_VALID;


        --=====================================================
        -- Evaluate the skip
        --=====================================================
        when CHECK_SKIP =>
            if (SKIP_COND = '1') then
                PC_OPCODE <= LD_SX;
            else
                PC_OPCODE <= HOLD;
            end if;
            -- restore flags after no-load op
            if (NO_LOAD = '1') then
                RESTORE <= '1';
            end if;


        --=====================================================
        -- Complete the JSR instruction
        --=====================================================
        when JSR_1 =>
            -- save the PC in AC3
            PC_TO_AC3  <= '1';
            -- load the PC from EA
            PC_OPCODE  <= LD_EA;
            NEXT_STATE <= FETCH_OPCODE;


        --=====================================================
        -- Complete the SAV instruction
        --=====================================================
        when SAV_1 =>
            -- pre-inc the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= INC1;
            SP_OPCODE  <= LD_SX;
            PC_OPCODE  <= HOLD;
            NEXT_STATE <= SAV_2;

        when SAV_2 =>
            -- save AC0
            USE_ACS  <= '1';
            ASY_SEL  <= "00";
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            -- increment the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= INC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= SAV_3;

        when SAV_3 =>
            -- save AC1
            USE_ACS  <= '1';
            ASY_SEL  <= "01";
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            -- increment the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= INC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= SAV_4;

        when SAV_4 =>
            -- save AC2
            USE_ACS  <= '1';
            ASY_SEL  <= "10";
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            -- increment the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= INC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= SAV_5;

        when SAV_5 =>
            -- save the frame pointer
            ACS_FP   <= '1';
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            -- increment the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= INC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= SAV_6;

        when SAV_6 =>
            -- save AC3
            USE_ACS  <= '1';
            ASY_SEL  <= "11";
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            -- copy the SP to FP
            FP_OPCODE  <= LD_SP;
            NEXT_STATE <= FETCH_OPCODE;


        --=====================================================
        -- Complete the RET instruction
        --=====================================================
        when RET_1 =>
            -- restore the PC and CBIT
            ACS_DIN    <= '1';
            PC_OPCODE  <= LDR;
            SET_C      <= '1';
            ADDR_OX    <= SP;
            -- decrement the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= DEC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= RET_2;

        when RET_2 =>
            -- restore AC3 and the frame pointer
            ACS_DIN    <= '1';
            USE_ACD    <= '1';
            ADY_SEL    <= "11";
            ACC_LOAD   <= '1';
            FP_OPCODE  <= LDR;
            ADDR_OX    <= SP;
            -- decrement the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= DEC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= RET_3;

        when RET_3 =>
            -- restore AC2
            ACS_DIN    <= '1';
            USE_ACD    <= '1';
            ADY_SEL    <= "10";
            ACC_LOAD   <= '1';
            ADDR_OX    <= SP;
            -- decrement the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= DEC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= RET_4;

        when RET_4 =>
            -- restore AC1
            ACS_DIN    <= '1';
            USE_ACD    <= '1';
            ADY_SEL    <= "01";
            ACC_LOAD   <= '1';
            ADDR_OX    <= SP;
            -- decrement the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= DEC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= RET_5;

        when RET_5 =>
            -- restore AC0
            ACS_DIN    <= '1';
            USE_ACD    <= '1';
            ADY_SEL    <= "00";
            ACC_LOAD   <= '1';
            ADDR_OX    <= SP;
            -- decrement the stack pointer
            SX_BSEL    <= SEL_SP;
            SX_OPCODE  <= DEC1;
            SP_OPCODE  <= LD_SX;
            NEXT_STATE <= FETCH_OPCODE;


        --=====================================================
        -- Complete the PSHA instruction
        --=====================================================
        when PSHA_1 =>
            ADDR_OX  <= SP;
            MMWRITE  <= '1';
            NEXT_STATE <= FETCH_OPCODE;


        --=====================================================
        -- CPU Halt
        --=====================================================
        when HALT_1 =>
            PC_OPCODE <= HOLD;
            NEXT_STATE <= HALT_1;

           -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
           -- Halt should jump to the virtual console
           -- This is not implemented yet
           -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        --=====================================================
        -- Unimplemeted trap
        --=====================================================
        when others =>
            PC_OPCODE <= HOLD;
            NEXT_STATE <= UII_1;

        end case;

    end process;


    --================================================================
    -- Read/Write Status output pin
    --================================================================
    R_W  <= not MMWRITE;
    IORW <= not IOWRITE;


    --================================================================
    -- Skip control
    --================================================================
    SKIP_CONTROL:
    process(SKIP_CTL, CBIT, ZBIT, DONE, BUSY, INTEN, PWR_GOOD)
    begin
        case SKIP_CTL is
            when SKP =>     -- skip always
                SKIP_COND <= '1';
            when SKC =>     -- skip if carry zero
                SKIP_COND <= not CBIT;
            when SNC =>     -- skip if carry non-zero
                SKIP_COND <= CBIT;
            when SZR =>     -- skip if result zero
                SKIP_COND <= ZBIT;
            when SNR =>     -- skip if result non-zero
                SKIP_COND <= not ZBIT;
            when SEZ =>     -- skip if either zero
                SKIP_COND <= ZBIT or (not CBIT);
            when SBN =>     -- skip if both non-zero
                SKIP_COND <= (not ZBIT) and CBIT;
            when SKPBZ =>   -- skip if busy is zero
                SKIP_COND <= not DONE;
            when SKPDN =>   -- skip if done is set
                SKIP_COND <= DONE;
            when SKPDZ =>   -- skip if done is zero
                SKIP_COND <= not BUSY;
            when SKPBN =>   -- skip if busy is set
                SKIP_COND <= BUSY;
            when SKPIE =>   -- skip if Int enabled
                SKIP_COND <= INTEN;
            when SKPID =>   -- skip if Int disabled
                SKIP_COND <= not INTEN;
            when SKPPF =>   -- skip if power failed
                SKIP_COND <= not PWR_GOOD;
            when SKPPO =>   -- skip if power OK
                SKIP_COND <= PWR_GOOD;
            when others =>  -- no skip
                SKIP_COND <= '0';
        end case;
    end process;


    --================================================================
    -- ALU opcode Mux
    --================================================================
    ALU_OPCODE_MUX:
    process(USE_ALU, ALX_OPCODE, ALY_OPCODE)
    begin
        -- Usually ALU control comes from the decoder
        -- but occasionally we want to override that control
        ALU_OPCODE <= ALX_OPCODE;
        if (USE_ALU = '1') then
            ALU_OPCODE <= ALY_OPCODE;
        end if;
    end process;


    --================================================================
    -- Register source-select Mux
    --================================================================
    SOURCE_SELECT_MUX:
    process(ASX_SEL, USE_ACS, ASY_SEL)
    begin
        -- Usually source select control comes from the decoder
        -- but occasionally we want to override that control
        ACS_SEL <= ASX_SEL;
        if (USE_ACS = '1') then
            ACS_SEL <= ASY_SEL;
        end if;
    end process;


    --================================================================
    -- Destination resiter select
    --================================================================
    DESTINATION_REGISTER_SELECT:
    process(BMUX_SEL, USE_ACD, ADY_SEL, LDB_OP, STB_OP, ASX_SEL)
    begin
        -- Usually destination select control comes from the decoder
        -- but occasionally we want to override that control
        DEST_SEL <= BMUX_SEL;
        if (USE_ACD = '1') then
            DEST_SEL <= ADY_SEL;
        end if;
        -- The src and dst were swapped for the LDB instruction
        -- due to logic optimization reasons
        if ((LDB_OP = '1') or (STB_OP = '1')) then
            DEST_SEL <= ASX_SEL;
        end if;
    end process;


    --=====================================================
    -- Sync Status Output flip-flop
    --=====================================================
    SYNC_STATUS_FLIP_FLOP:
    process(CLK)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (NEXT_STATE = FETCH_OPCODE) then
                SYNC <= '1';
            else
                SYNC <= '0';
            end if;
        end if;
        end if;
    end process;


    --================================================================
    -- Accumulator AC0
    --================================================================
    ACCUMULATOR_0:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (AC0_OPCODE = LDR) then
                AC0 <= RBUS;
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            AC0 <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Accumulator AC1
    --================================================================
    ACCUMULATOR_1:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (AC1_OPCODE = LDR) then
                AC1 <= RBUS;
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            AC1 <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Accumulator AC2
    --================================================================
    ACCUMULATOR_2:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (AC2_OPCODE = LDR) then
                AC2 <= RBUS;
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            AC2 <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Accumulator AC3
    --================================================================
    ACCUMULATOR_3:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            if (AC3_OPCODE = LDR) then
                AC3 <= RBUS;
            end if;
            if (PC_TO_AC3 = '1') then
                AC3 <= '0' & PC(15 downto 1);
            end if;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            AC3 <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Scratch Register SR1
    --================================================================
    SCRATCH_REGISTER_1:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            case SR1_OPCODE is
                when LDR =>
                    SR1 <= RBUS;
                when LD_DB =>
                    SR1 <= DATA_IN;
                when others =>
            end case;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            SR1 <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Stack Pointer (SP)
    --================================================================
    STACK_POINTER:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            case SP_OPCODE is
                when LDR =>
                    SP <= RBUS(14 downto 0) & '0';
                when LD_FP =>
                    SP <= FP;
                when LD_SX =>
                    SP <= SX;
                when others =>
            end case;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            SP <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Frame Pointer (FP)
    --================================================================
    FRAME_POINTER:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            case FP_OPCODE is
                when LDR =>
                    FP <= RBUS(14 downto 0) & '0';
                when LD_SP =>
                    FP <= SP;
                when others =>
            end case;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            FP <= (others => '0');
        end if;
    end process;


    --================================================================
    -- Program Counter (PC)
    --================================================================
    PROGRAM_COUNTER:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            case PC_OPCODE is
                when LD_SX =>
                    PC <= SX;
                when LDR =>
                    PC <= RBUS(14 downto 0) & '0';
                when LD_EA =>
                    PC <= EA;
                when others =>
            end case;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            PC <= x"0100";
        end if;
    end process;


    --=================================================
    -- Effective Address register (EA)
    --=================================================
    EA_REGISTER:
    process(CLK, MY_RESET)
    begin
        if (CLK = '0' and CLK'event) then
        if (FEN = '1') then
            case EA_OPCODE is
                when LD_SX =>
                    EA <= SX;
                when LD_DB =>
                    EA <= DATA_IN(14 downto 0) & '0';
                when LD_SR1 =>
                    EA <= SR1(14 downto 0) & '0';
                when LD_ZP =>
                    EA <= "0000000" & OPREG(7 downto 0) & '0';
                when others =>
            end case;
        end if;
        end if;
        -- reset state
        if (MY_RESET = '1') then
            EA <= (others => '0');
        end if;
    end process;


    --===================================
    -- Instantiate the ALU
    --===================================
    ALU1:
    ALU port map (
        RBUS      => RBUS,
        CBIT      => CBIT,
        ZBIT      => ZBIT,
        ABUS      => AMUX,
        BBUS      => BMUX,
        ALU_OP    => ALU_OPCODE,
        SHIFT_CTL => SHIFT_CTL,
        CARRY_CTL => CARRY_CTL,
        UPDATE_C  => UPDATE_C,
        UPDATE_Z  => UPDATE_Z,
        RESTORE   => RESTORE,
        SET_C     => SET_C,
        RESET     => MY_RESET,
        FEN       => FEN,
        CLK       => CLK
      );


    --=============================================
    -- Instantiate the 16-bit Address Adder
    --=============================================
    ADDR1:
    ADDR port map (
        SX   => SX,
        BX   => BX,
        DISP => OPREG(7 downto 0),
        OP   => SX_OPCODE
      );


    --=========================================
    -- Instantiate the instruction decoder
    --=========================================
    DECODER:
    DECODE port map (
        DECODE_IN => OPREG,
        FORMAT    => FORMAT,
        ADDR_MODE => ADDR_MODE,
        SRC_SEL   => ASX_SEL,
        DST_SEL   => BMUX_SEL,
        ALU_OP    => ALX_OPCODE,
        SHIFT_CTL => SHIFT_DEC,
        CARRY_CTL => CARRY_CTL,
        NO_LOAD   => NO_LOAD,
        SKIP_CTL  => SKIP_CTL,
        FLOW_CTL  => FLOW_CTL,
        IND_CTL   => IND_CTL,
        IDX_CTL   => IDX_CTL,
        XFER_CTL  => XFER_CTL,
        IOU_CTL   => IOU_CTL,
        EXT_OP    => EXT_OP
      );

end BEHAVIORAL;
