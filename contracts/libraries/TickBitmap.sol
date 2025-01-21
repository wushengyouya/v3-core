// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickBitmap {
    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8); // tick / 2^8 = tick / 256
        bitPos = uint8(tick % 256); // tick的位置一定位于256以内
    }

    /// @notice 添加移除流动性会调用标记BitMap
    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        require(tick % tickSpacing == 0); // ensure that the tick is spaced
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        // 异或，同为0，异为1
        // 假设bitPos为3,  self[wordPos]为 00000000
        // mask: 00001000
        // 00000000 ^ 00001000 = 00001000
        self[wordPos] ^= mask;
    }

    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        // TODO: understand, 不太理解获取下一个tick,当前tick参与运算为什么要除以tickSpacing,可以不除吗？
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

        // true: token0 -> token1
        if (lte) {
            // 获取tick映射的键，和bit位
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // all the 1s at or to the right of the current bitPos
            // (1 << bitPos + 1) -1 = (1 << bitPos) - 1 + (1 << bitPos)
            // 如果bitPos=3:
            // (1 << 3) = 1000, -1 后会反转成为 0111
            // (1 << 3) - 1 + (1 << 3) = 7 + 8 = 15  二进制为: 1111
            // (1 << (3 + 1)) - 1 = (1 << 4) - 1 = 16 - 1 = 15
            // 假设self[wordPos] 是 10110101 (binary),  bitPos = 3
            // 10110101 & 00001111 => 00001010 找到currentTick右边的存在流动性的Tick
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            // TODO: understand，不理解下面的减法的运算
            // BitMath.mostSignificantBit 返回最高位的有效bit位，也就是右边第一位
            // 00001111 返回最高有效位
            //     ^
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // token1 -> token0

            // start from the word of the next tick, since the current tick state doesn't matter
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // all the 1s at or to the left of the bitPos
            // (1 << 3) = 1000, -1 后会反转成为 0111
            // ~(0111) = 1000
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // TODO: understand
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            // BitMath.leastSignificantBit 返回最低位的有效bit位，也就是右边第一位
            // 11110000 返回最低有效位
            //    ^
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }
}
