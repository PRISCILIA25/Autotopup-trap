    function respondWithPermitAndTopUp(
        address token,
        address from,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        if (amount == 0) {
            emit TopUpFailed(token, from, amount, REASON_ZERO, "", msg.sender);
            return;
        }

        // call permit via low-level call to support tokens gracefully
        (bool okPermit, bytes memory pData) = token.call(
            abi.encodeWithSignature("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)", from, address(this), amount, deadline, v, r, s)
        );

        if (!okPermit) {
            emit TopUpFailed(token, from, amount, REASON_PERMIT, pData, msg.sender);
            return;
        }

        // then transferFrom
        (bool ok, bytes memory data) = _transferFrom(token, from, SAFE, amount);
        if (!ok) {
            emit TopUpFailed(token, from, amount, REASON_TF, data, msg.sender);
            return;
        }
        if (data.length == 0 || _decodeBool(data)) {
            emit TopUp(token, from, SAFE, amount, msg.sender);
        } else {
            emit TopUpFailed(token, from, amount, REASON_TF, data, msg.sender);
        }
    }
}
