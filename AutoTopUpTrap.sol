// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITrap {
    function collect() external view returns (bytes memory);
    function shouldRespond(bytes[] calldata collectOutputs) external pure returns (bool, bytes memory);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// AutoTopUpTrap for 6ixty token
/// - TOKEN: 0xab16D6FF7295Dfc304c3C816c7e6d62926d2f7A4
/// - SAFE (monitored): 0xD78a2D9D050bd1C8bef581Aa6Da507193708776A
/// - FUNDING (source): 0x69375A9b81633Ce35e758a5972cd037E3Aca1FAa
contract Trap is ITrap {
    address public constant TOKEN = 0xab16D6FF7295Dfc304c3C816c7e6d62926d2f7A4;
    address public constant SAFE  = 0xD78a2D9D050bd1C8bef581Aa6Da507193708776A;
    address public constant FUNDING = 0x69375A9b81633Ce35e758a5972cd037E3Aca1FAa;

    // MIN_BASE = 500_000 tokens (scaled by decimals in collect())
    uint256 public constant MIN_BASE = 500_000;

    // Restore to RESTORE_PERCENT of previous sample when triggered (80%)
    uint256 public constant RESTORE_PERCENT = 80;

    // collect() returns (safeBalance, sampleBlock, decimals)
    function collect() external view override returns (bytes memory) {
        uint8 dec;
        try IERC20(TOKEN).decimals() returns (uint8 d) {
            dec = d;
        } catch {
            dec = 18;
        }
        uint256 bal = IERC20(TOKEN).balanceOf(SAFE);
        uint256 blk = block.number;
        return abi.encode(bal, blk, dec);
    }

    // shouldRespond uses two samples (most recent two supplied) and is pure.
    // Each sample expected: abi.encode(balance, sampleBlock, decimals)
    // Triggers when:
    //   - latest < MIN_BASE * 10**dec  (absolute minimum)
    //   - OR latest < prev/2  (50% drop, rounding-aware)
    // Withdraw amount computed so SAFE is restored to RESTORE_PERCENT% of prev (i.e., top up to that level)
    // Payload: abi.encode(TOKEN, FUNDING, withdrawAmount)
    function shouldRespond(bytes[] calldata collectOutputs) external pure override returns (bool, bytes memory) {
        if (collectOutputs.length < 2) return (false, "");

        (uint256 aBal, uint256 aBlk, uint8 aDec) = abi.decode(collectOutputs[0], (uint256, uint256, uint8));
        (uint256 bBal, uint256 bBlk, uint8 bDec) = abi.decode(collectOutputs[1], (uint256, uint256, uint8));

        uint8 dec = aDec >= bDec ? aDec : bDec;

        bool aIsLatest = aBlk >= bBlk;
        uint256 latestBal = aIsLatest ? aBal : bBal;
        uint256 prevBal   = aIsLatest ? bBal : aBal;

        if (prevBal == 0) return (false, "");
        if (latestBal == prevBal) return (false, "");

        // scaled absolute minimum
        uint256 minAbs = MIN_BASE * (10 ** uint256(dec));

        // 1) check absolute minimum
        if (latestBal < minAbs) {
            uint256 restoreTarget = (prevBal * RESTORE_PERCENT) / 100;
            if (latestBal >= restoreTarget) return (false, "");
            uint256 withdrawAmount = restoreTarget - latestBal;
            bytes memory payload = abi.encode(TOKEN, FUNDING, withdrawAmount);
            return (true, payload);
        }

        // 2) check 50% drop with rounding-aware compare
        if (latestBal * 2 < prevBal + (prevBal % 2)) {
            uint256 restoreTarget = (prevBal * RESTORE_PERCENT) / 100;
            if (latestBal >= restoreTarget) return (false, "");
            uint256 withdrawAmount = restoreTarget - latestBal;
            bytes memory payload = abi.encode(TOKEN, FUNDING, withdrawAmount);
            return (true, payload);
        }

        return (false, "");
    }
}
