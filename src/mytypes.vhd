
--========================================================================
-- mytypes.vhd ::  Nova global type definitions
--
-- (c) Scott L. Baker, Sierra Circuit Design
--========================================================================

library IEEE;
use IEEE.std_logic_1164.ALL;


package my_types  IS

    --=======================================
    -- opcode formats
    --=======================================
    type OP_FORMAT_TYPE is (
             ALU_FORMAT,
             MEM_FORMAT,
             LDA_FORMAT,
             STA_FORMAT,
             IOU_FORMAT,
             EXT_FORMAT,
             UII_FORMAT
          );


    --=======================================
    -- Addressing modes
    --=======================================
    type ADDR_MODE_TYPE is (
             ADM_OK,
             ADM_EA
          );


    --=======================================
    -- ALU operations
    --=======================================
    type ALU_OP_TYPE is (
             COM,  -- complement
             NEG,  -- negate
             INC,  -- increment
             DEC,  -- decrement
             ADC,  -- add complement
             SUB,  -- subtract
             ADD,  -- add
             ANA,  -- logical and
             TA    -- transfer A
          );


    --=======================================
    -- Shifter control
    --=======================================
    type SHIFT_CTL_TYPE is (
             NOP,    -- no shift
             LEFT,   -- shift left
             RIGHT,  -- shift right
             SWAP    -- swap hi and lo bytes
          );


    --=======================================
    -- Carry control
    --=======================================
    type CARRY_CTL_TYPE is (
             NOP,    -- no change
             CLEAR,  -- clear carry
             SET,    -- set carry
             INVERT  -- invert carry
          );


    --=======================================
    -- Skip control
    --=======================================
    type SKIP_CTL_TYPE is (
             NOP,   -- no skip
             SKP,   -- skip
             SKC,   -- skip if carry zero
             SNC,   -- skip if carry non-zero
             SZR,   -- skip if result zero
             SNR,   -- skip if result non-zero
             SEZ,   -- skip if either zero
             SBN,   -- skip if both non-zero
             SKPBN, -- skip if busy is set
             SKPBZ, -- skip if busy is zero
             SKPDN, -- skip if done is set
             SKPDZ, -- skip if done is zero
             SKPIE, -- skip if Int enabled
             SKPID, -- skip if Int disabled
             SKPPF, -- skip if power failed
             SKPPO  -- skip if power OK
          );


    --=======================================
    -- Program flow-control functions
    --=======================================
    type FLOW_CTL_TYPE is (
             JMP,  -- jump to address
             JSR,  -- jump to subroutine
             ISZ,  -- incr and skip if zero
             DSZ   -- decr and skip if zero
          );


    --=======================================
    -- address index control
    --=======================================
    type IDX_CTL_TYPE is (
             ZPG,   -- page zero
             REL,   -- PC relative
             IDX2,  -- index reg 2
             IDX3   -- index reg 3
          );


    --=======================================
    -- address index control
    --=======================================
    type XFER_CTL_TYPE is (
             NOP,   -- no I/O transfer
             DIA,   -- data in from buffer A
             DOA,   -- data out  to buffer A
             DIB,   -- data in from buffer B
             DOB,   -- data out  to buffer B
             DIC,   -- data in from buffer C
             DOC,   -- data out  to buffer C
             SKP    -- skip on condition
          );


    --=======================================
    -- I/O Unit control
    --=======================================
    type IOU_CTL_TYPE is (
             NOP,   -- no operation
             SBCD,  -- set busy; clear done
             CBCD,  -- clear busy and done
             PULSE  -- issue a pulse
          );


    --=======================================
    -- Extended opcodes
    --=======================================
    type EXT_OP_TYPE is (
             MUL,   -- unsigned multiply
             DIV,   -- unsigned divide
             MULS,  -- signed multiply
             DIVS,  -- signed divide
             SAV,   -- save registers to stack
             RET,   -- return from subroutine
             PSHA,  -- push accumulator
             POPA,  -- push accumulator
             MTSP,  -- move to stack pointer
             MFSP,  -- move from stack pointer
             MTFP,  -- move to frame pointer
             MFFP,  -- move from frame pointer
             LDB,   -- load  byte
             STB,   -- store byte
             NOP    -- no operation
          );


    --=======================================
    -- Address adder operations
    --=======================================
    type  SX_OP_TYPE is (
             REL,      --  Relative
             INC2,     --  Increment by 2
             INC1,     --  Increment by 1
             DEC1      --  Decrement by 1
          );


END my_types;
