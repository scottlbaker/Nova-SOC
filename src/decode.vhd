--========================================================================
-- decode.vhd ::  Nova instruction decoder
--
-- (c) Scott L. Baker, Sierra Circuit Design
--========================================================================

library IEEE;
use IEEE.std_logic_1164.all;

use work.my_types.all;


entity DECODE is
    port (

        -- decoder input
        DECODE_IN : in  std_logic_vector(15 downto 0);

        -- opcode classes
        FORMAT    : out OP_FORMAT_TYPE;                -- opcode format
        ADDR_MODE : out ADDR_MODE_TYPE;                -- address mode

        -- ALU opcode fields
        SRC_SEL   : out std_logic_vector(1 downto 0);  -- Source register
        DST_SEL   : out std_logic_vector(1 downto 0);  -- Destination reg
        ALU_OP    : out ALU_OP_TYPE;                   -- ALU micro-op
        SHIFT_CTL : out SHIFT_CTL_TYPE;                -- Shifter control
        CARRY_CTL : out CARRY_CTL_TYPE;                -- Carry control
        NO_LOAD   : out std_logic;                     -- Don't load the dest
        SKIP_CTL  : out SKIP_CTL_TYPE;                 -- Skip control

        -- Memory xfer opcode fields
        FLOW_CTL  : out FLOW_CTL_TYPE;                 -- Program flow control
        IND_CTL   : out std_logic;                     -- Indirect access
        IDX_CTL   : out IDX_CTL_TYPE;                  -- Index control

        -- I/O opcode fields
        XFER_CTL  : out XFER_CTL_TYPE;                 -- Transfer control
        IOU_CTL   : out IOU_CTL_TYPE;                  -- I/O device control

        EXT_OP    : out EXT_OP_TYPE                    -- I/O device control
       );
end DECODE;


architecture BEHAVIORAL of DECODE is

    --=================================================================
    -- signal definitions
    --=================================================================

    -- extended opcode group 1
    signal GROUP1 : std_logic_vector(3 downto 0);


begin

    GROUP1 <= DECODE_IN(12 downto 11) & DECODE_IN(7 downto 6);

    --=========================================================
    -- Decode the opcode and addressing mode
    --=========================================================
    DECODE_OPCODE_AND_ADDRESS_MODE:
    process(DECODE_IN, GROUP1)
    begin

        --===================================================
        -- Set the default states for the addressing modes
        --===================================================
        FORMAT    <= UII_FORMAT;
        ADDR_MODE <= ADM_OK;

        SRC_SEL   <= "00";
        DST_SEL   <= "00";
        NO_LOAD   <= '0';
        IND_CTL   <= '0';
        ALU_OP    <= TA;
        FLOW_CTL  <= JMP;
        IDX_CTL   <= ZPG;
        SHIFT_CTL <= NOP;
        CARRY_CTL <= NOP;
        SKIP_CTL  <= NOP;
        XFER_CTL  <= NOP;
        IOU_CTL   <= NOP;
        EXT_OP    <= NOP;

        --====================================
        -- Arithmetic/Logic Instructions
        --====================================
        if (DECODE_IN(15) = '1') then

            FORMAT    <= ALU_FORMAT;

            SRC_SEL <= DECODE_IN(14 downto 13);
            DST_SEL <= DECODE_IN(12 downto 11);

            -- ALU control
            case DECODE_IN(10 downto 8) is

                when "000" =>
                    ALU_OP <= COM;
                when "001" =>
                    ALU_OP <= NEG;
                when "010" =>
                    ALU_OP <= TA;
                when "011" =>
                    ALU_OP <= INC;
                when "100" =>
                    ALU_OP <= ADC;
                when "101" =>
                    ALU_OP <= SUB;
                when "110" =>
                    ALU_OP <= ADD;
                when "111" =>
                    ALU_OP <= ANA;
                when others =>

            end case;

            -- shift control
            case DECODE_IN(7 downto 6) is
                when "00" =>
                    SHIFT_CTL <= NOP;
                when "01" =>
                    SHIFT_CTL <= LEFT;
                when "10" =>
                    SHIFT_CTL <= RIGHT;
                when "11" =>
                    SHIFT_CTL <= SWAP;
                when others =>
            end case;

            -- carry control
            case DECODE_IN(5 downto 4) is
                when "00" =>
                    CARRY_CTL <= NOP;
                when "01" =>
                    CARRY_CTL <= CLEAR;
                when "10" =>
                    CARRY_CTL <= SET;
                when "11" =>
                    CARRY_CTL <= INVERT;
                when others =>
            end case;

            NO_LOAD <= DECODE_IN(3);

            -- skip control
            case DECODE_IN(2 downto 0) is
                when "000" =>
                    SKIP_CTL <= NOP;  -- no skip
                when "001" =>
                    SKIP_CTL <= SKP;  -- skip
                when "010" =>
                    SKIP_CTL <= SKC;  -- skip if carry zero
                when "011" =>
                    SKIP_CTL <= SNC;  -- skip if carry non-zero
                when "100" =>
                    SKIP_CTL <= SZR;  -- skip if result zero
                when "101" =>
                    SKIP_CTL <= SNR;  -- skip if result non-zero
                when "110" =>
                    SKIP_CTL <= SEZ;  -- skip if either zero
                when "111" =>
                    SKIP_CTL <= SBN;  -- skip if both zero
                when others =>
            end case;

        else

            case DECODE_IN(15 downto 13) is

                --=================================
                -- Memory access Instructions
                --=================================
                when "000" =>

                    FORMAT    <= MEM_FORMAT;
                    ADDR_MODE <= ADM_EA;

                    -- Program flow control
                    case DECODE_IN(12 downto 11) is
                        when "00" =>
                            FLOW_CTL <= JMP;  -- jump to address
                        when "01" =>
                            FLOW_CTL <= JSR;  -- jump to subroutine
                        when "10" =>
                            FLOW_CTL <= ISZ;  -- incr and skip if zero
                            ALU_OP   <= INC;
                            SKIP_CTL <= SZR;
                        when "11" =>
                            FLOW_CTL <= DSZ;  -- decr and skip if zero
                            ALU_OP   <= DEC;
                            SKIP_CTL <= SZR;
                        when others =>
                    end case;

                    IND_CTL <= DECODE_IN(10);

                    -- index control
                    case DECODE_IN(9 downto 8) is
                        when "00" =>
                            IDX_CTL <= ZPG;   -- page zero
                        when "01" =>
                            IDX_CTL <= REL;   -- PC relative
                        when "10" =>
                            IDX_CTL <= IDX2;  -- index reg 2
                        when "11" =>
                            IDX_CTL <= IDX3;  -- index reg 3
                        when others =>
                    end case;


                --=================================
                -- Load accumulator Instructions
                --=================================
                when "001" =>

                    FORMAT    <= LDA_FORMAT;
                    ADDR_MODE <= ADM_EA;

                    DST_SEL <= DECODE_IN(12 downto 11);
                    IND_CTL <= DECODE_IN(10);

                    -- index control
                    case DECODE_IN(9 downto 8) is
                        when "00" =>
                            IDX_CTL <= ZPG;   -- page zero
                        when "01" =>
                            IDX_CTL <= REL;   -- PC relative
                        when "10" =>
                            IDX_CTL <= IDX2;  -- index reg 2
                        when "11" =>
                            IDX_CTL <= IDX3;  -- index reg 3
                        when others =>
                    end case;


                --=================================
                -- Store accumulator Instructions
                --=================================
                when "010" =>

                    FORMAT    <= STA_FORMAT;
                    ADDR_MODE <= ADM_EA;

                    SRC_SEL <= DECODE_IN(12 downto 11);
                    IND_CTL <= DECODE_IN(10);

                    -- index control
                    case DECODE_IN(9 downto 8) is
                        when "00" =>
                            IDX_CTL <= ZPG;   -- page zero
                        when "01" =>
                            IDX_CTL <= REL;   -- PC relative
                        when "10" =>
                            IDX_CTL <= IDX2;  -- index reg 2
                        when "11" =>
                            IDX_CTL <= IDX3;  -- index reg 3
                        when others =>
                    end case;


                --=================================
                -- I/O Instructions
                --=================================
                when "011" =>

                    -- Device code 1 Extended opcodes
                    if (DECODE_IN(5 downto 0) = "000001") then

                        FORMAT <= EXT_FORMAT;

                        case DECODE_IN(10 downto 8) is

                            when "000" =>

                                case DECODE_IN(7 downto 6) is

                                    -- move to frame pointer
                                    when "00" =>
                                        SRC_SEL  <= DECODE_IN(12 downto 11);
                                        EXT_OP <= MTFP;

                                    -- move from frame pointer
                                    when "10" =>
                                        DST_SEL <= DECODE_IN(12 downto 11);
                                        EXT_OP <= MFFP;

                                    -- undefined opcodes
                                    when others =>

                                end case;

                            -- load byte
                            when "001" =>
                                EXT_OP <= LDB;
                                DST_SEL <= DECODE_IN(7 downto 6);
                                SRC_SEL <= DECODE_IN(12 downto 11);

                            when "010" =>

                                case DECODE_IN(7 downto 6) is

                                    -- move to stack pointer
                                    when "00" =>
                                        SRC_SEL  <= DECODE_IN(12 downto 11);
                                        EXT_OP <= MTSP;

                                    -- move from stack pointer
                                    when "10" =>
                                        DST_SEL <= DECODE_IN(12 downto 11);
                                        EXT_OP <= MFSP;

                                    -- undefined opcodes
                                    when others =>

                                end case;

                            when "011" =>

                                case DECODE_IN(7 downto 6) is

                                    -- push onto stack
                                    when "00" =>
                                        SRC_SEL <= DECODE_IN(12 downto 11);
                                        EXT_OP <= PSHA;

                                    -- pop from stack
                                    when "10" =>
                                        DST_SEL <= DECODE_IN(12 downto 11);
                                        EXT_OP <= POPA;

                                    -- undefined opcodes
                                    when others =>

                                end case;

                            -- store byte
                            when "100" =>
                                EXT_OP <= STB;
                                DST_SEL <= DECODE_IN(7 downto 6);
                                SRC_SEL <= DECODE_IN(12 downto 11);

                            when "101" =>

                                case GROUP1 is

                                    -- save registers to stack
                                    when "0000" =>
                                        EXT_OP <= SAV;

                                    -- return from subroutine
                                    when "0010" =>
                                        EXT_OP <= RET;

                                    -- undefined opcodes
                                    when others =>

                                end case;


                            -- store byte
                            when "110" =>

                                case GROUP1 is

                                    -- unsigned multiply
                                    when "1011" =>
                                        EXT_OP <= MUL;

                                    -- unsigned divide
                                    when "1001" =>
                                        EXT_OP <= DIV;

                                    -- signed multiply
                                    when "1110" =>
                                        EXT_OP <= MULS;

                                    -- signed divide
                                    when "1100" =>
                                        EXT_OP <= DIVS;

                                    -- undefined opcodes
                                    when others =>

                                end case;

                            -- undefined opcodes
                            when others =>

                        end case;

                    else

                        FORMAT  <= IOU_FORMAT;
                        SRC_SEL <= DECODE_IN(12 downto 11);
                        DST_SEL <= DECODE_IN(12 downto 11);

                        -- transfer control
                        case DECODE_IN(10 downto 8) is
                            when "000" =>
                                XFER_CTL <= NOP;  -- no I/O transfer
                            when "001" =>
                                XFER_CTL <= DIA;  -- data in from buffer A
                            when "010" =>
                                XFER_CTL <= DOA;  -- data out  to buffer A
                            when "011" =>
                                XFER_CTL <= DIB;  -- data in from buffer B
                            when "100" =>
                                XFER_CTL <= DOB;  -- data out  to buffer B
                            when "101" =>
                                XFER_CTL <= DIC;  -- data in from buffer C
                            when "110" =>
                                XFER_CTL <= DOC;  -- data out  to buffer C
                            when "111" =>
                                XFER_CTL <= SKP;  -- skip on condition
                            when others =>
                        end case;

                        -- IOU control
                        if DECODE_IN(10 downto 8) = "111" then
                            -- check for device 0x3f special cases
                            if (DECODE_IN(5 downto 0) = "111111") then
                                case DECODE_IN(7 downto 6) is
                                    when "00" =>
                                        SKIP_CTL <= SKPIE; -- skip if Int enabled
                                    when "01" =>
                                        SKIP_CTL <= SKPID; -- skip if Int disabled
                                    when "10" =>
                                        SKIP_CTL <= SKPPF; -- skip if power fail
                                    when others =>
                                        SKIP_CTL <= SKPPO; -- skip if power OK
                                end case;
                            else
                                case DECODE_IN(7 downto 6) is
                                    when "00" =>
                                        SKIP_CTL <= SKPBN; -- skip if busy is set
                                    when "01" =>
                                        SKIP_CTL <= SKPBZ; -- skip if busy is zero
                                    when "10" =>
                                        SKIP_CTL <= SKPDN; -- skip if done is set
                                    when others =>
                                        SKIP_CTL <= SKPDZ; -- skip if done is zero
                                end case;
                            end if;
                        else
                            case DECODE_IN(7 downto 6) is
                                when "00" =>
                                    IOU_CTL <= NOP;   -- no operation
                                when "01" =>
                                    IOU_CTL <= SBCD;  -- set busy; clear done
                                when "10" =>
                                    IOU_CTL <= CBCD;  -- clear busy and done
                                when others =>
                                    IOU_CTL <= PULSE; -- issue a pulse
                            end case;
                        end if;

                    end if;

                when others =>

            end case;

        end if;

    end process;

end BEHAVIORAL;
