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

/// AutoTopUpTrap for 6ixty token (hardened)
contract Trap is ITrap {
    address public constant TOKEN = 0xab16D6FF7295Dfc304c3C816c7e6d62926d2f7A4;
    address public constant SAFE  = 0xD78a2D9D050bd1C8bef581Aa6Da507193708776A;
    address public constant FUNDING = 0x69375A9b81633Ce35e758a5972cd037E3Aca1FAa;

    // MIN_BASE = 500_000 tokens (base units; scaled in collect())
    uint256 public constant MIN_BASE = 500_000;

    // Restore to RESTORE_PERCENT of previous sample when triggered (80%)
    uint256 public constant RESTORE_PERCENT = 80;

    // Max decimals we accept to prevent huge exponents
    uint8 public constant MAX_DECIMALS = 36;

    /// collect() is defensive:
    /// - checks TOKEN has code (extcodesize)
    /// - tries decimals() and balanceOf(), but never reverts
    /// Returns abi.encode(balance, block.number, decimals)
    function collect() external view override returns (bytes memory) {
        uint8 dec = 18;
        uint256 bal = 0;
        uint256 blk = block.number;

        address t = TOKEN;
        uint256 size;
        assembly { size := extcodesize(t) }

        if (size > 0) {
            // token looks like a contract, try to read decimals & balanceOf safely
            try IERC20(t).decimals() returns (uint8 d) {
                // clamp decimals to a sane max
                dec = d > MAX_DECIMALS ? MAX_DECIMALS : d;
            } catch {
                dec = 18;
            }

            try IERC20(t).balanceOf(SAFE) returns (uint256 b) {
                bal = b;
            } catch {
                bal = 0;
            }
        } else {
            // not a contract: leave bal=0, dec=18
            bal = 0;
            dec = 18;
        }

        return abi.encode(bal, blk, dec);
    }

    // helper: compute 10**dec safely (dec <= MAX_DECIMALS)
    function _scale(uint8 dec) internal pure returns (uint256) {
        if (dec > MAX_DECIMALS) dec = MAX_DECIMALS;
        uint256 s = 1;
        for (uint8 i = 0; i < dec; i++) {
            s = s * 10;
        }
        return s;
    }

    // shouldRespond is pure and defensive:
    // - guard against empty collectOutputs entries
    // - normalize sample ordering by block number
    // - prefer identical decimals, else fallback conservatively
    function shouldRespond(bytes[] calldata collectOutputs) external pure override returns (bool, bytes memory) {
        // require at least two samples, and that they are not empty blobs
        if (collectOutputs.length < 2) return (false, "");
        if (collectOutputs[0].length == 0 || collectOutputs[1].length == 0) return (false, "");

        // decode samples (each sample = abi.encode(balance, sampleBlock, decimals))
        (uint256 aBal, uint256 aBlk, uint8 aDec) = abi.decode(collectOutputs[0], (uint256, uint256, uint8));
        (uint256 bBal, uint256 bBlk, uint8 bDec) = abi.decode(collectOutputs[1], (uint256, uint256, uint8));

        // choose decimals: prefer equality; otherwise use non-zero if available, else default 18
        uint8 dec;
        if (aDec == bDec) {
            dec = aDec;
        } else if (aDec != 0 && bDec == 0) {
            dec = aDec;
        } else if (bDec != 0 && aDec == 0) {
            dec = bDec;
        } else {
            // both non-equal and non-zero -> pick the smaller conservatively
            dec = aDec < bDec ? aDec : bDec;
        }
        if (dec == 0) dec = 18;
        if (dec > MAX_DECIMALS) dec = MAX_DECIMALS;

        // normalize by block number: latest = sample with greater block
        bool aIsLatest = aBlk >= bBlk;
        uint256 latestBal = aIsLatest ? aBal : bBal;
        uint256 prevBal   = aIsLatest ? bBal : aBal;

        // sanity guards
        if (prevBal == 0) return (false, "");
        if (latestBal == prevBal) return (false, "");

        // compute scaled absolute minimum safely
        uint256 scale = _scale(dec);
        // protect against unexpected overflow (shouldn't happen with clamp)
        uint256 minAbs = MIN_BASE * scale;

        // 1) absolute-minimum check (if latest < MIN_BASE * 10**dec)
        if (latestBal < minAbs) {
            uint256 restoreTarget = (prevBal * RESTORE_PERCENT) / 100;
            if (latestBal >= restoreTarget) return (false, "");
            uint256 withdrawAmount = restoreTarget - latestBal;
            return (true, abi.encode(TOKEN, FUNDING, withdrawAmount));
        }

        // 2) 50% drop check (rounding-aware)
        // Equivalent to: latest < ceil(prev/2)
        if (latestBal * 2 < prevBal + (prevBal % 2)) {
            uint256 restoreTarget = (prevBal * RESTORE_PERCENT) / 100;
            if (latestBal >= restoreTarget) return (false, "");
            uint256 withdrawAmount = restoreTarget - latestBal;
            return (true, abi.encode(TOKEN, FUNDING, withdrawAmount));
        }

        // nothing to do
        return (false, "");
    }
}
