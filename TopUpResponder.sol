// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract TopUpResponder {
    // SAFE destination (monitored wallet)
    address public constant SAFE = 0xD78a2D9D050bd1C8bef581Aa6Da507193708776A;

    // FUNDING: not enforced in responder (caller supplies 'from'), but PoC uses funding wallet: 0x6937...
    // Only allow operator to call response functions
    address public constant ALLOWED_CALLER = 0x0c5832C5fa862E1dBc765408f7987AAd4F7E7647;

    // reason codes as bytes32 (gas efficient)
    bytes32 public constant REASON_ZERO = bytes32("ZERO");
    bytes32 public constant REASON_UNAUTH = bytes32("UNAUTH");
    bytes32 public constant REASON_TF = bytes32("TF");
    bytes32 public constant REASON_PERMIT = bytes32("PERMIT");

    event TopUp(address indexed token, address indexed from, address indexed to, uint256 amount, address caller);
    event TopUpFailed(address indexed token, address indexed from, uint256 amount, bytes32 reason, bytes data, address caller);
    event Unauthorized(address indexed caller, address token, address from, uint256 amount);

    // low-level transferFrom wrapper
    function _transferFrom(address token, address from, address to, uint256 amount) internal returns (bool, bytes memory) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        return (ok, data);
    }

    function _decodeBool(bytes memory data) internal pure returns (bool) {
        if (data.length < 32) return false;
        uint256 w;
        assembly { w := mload(add(data, 32)) }
        return w != 0;
    }

    // Primary responder: called by Drosera when trap triggers
    // Signature matches drosera.toml response_function below
    function respondAndTopUp(address token, address from, uint256 amount) external {
        if (msg.sender != ALLOWED_CALLER) {
            emit Unauthorized(msg.sender, token, from, amount);
            return;
        }
        if (amount == 0) {
            emit TopUpFailed(token, from, amount, REASON_ZERO, "", msg.sender);
            return;
        }

        (bool ok, bytes memory data) = _transferFrom(token, from, SAFE, amount);
        if (!ok) {
            emit TopUpFailed(token, from, amount, REASON_TF, data, msg.sender);
            return;
        }

        if (data.length == 0) {
            emit TopUp(token, from, SAFE, amount, msg.sender);
            return;
        }

        bool success = _decodeBool(data);
        if (success) {
            emit TopUp(token, from, SAFE, amount, msg.sender);
        } else {
            emit TopUpFailed(token, from, amount, REASON_TF, data, msg.sender);
        }
    }

    // Permit flow: owner signs permit offline (EIP-2612) and operator supplies signature fields
    function respondWithPermitAndTopUp(
        address token,
        address from,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        if (msg.sender != ALLOWED_CALLER) {
            emit Unauthorized(msg.sender, token, from, amount);
            return;
        }
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
