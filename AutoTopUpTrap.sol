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
