//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOracle} from "../../src/interfaces/IOracle.sol";

import {ISwapperSwaps, MinAmountOutData, MinAmountOutKind} from "vault-v2/ReaperSwapper.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "forge-std/console.sol";

contract ReaperSwapperMock {
    using FixedPointMathLib for uint256;

    IOracle oracle;
    address underlyingToken;
    address paymentToken;

    constructor(IOracle _oracle, address _underlyingToken, address _paymentToken) {
        oracle = _oracle;
        underlyingToken = _underlyingToken;
        paymentToken = _paymentToken;
    }

    function swapUniV2(address tokenIn, address tokenOut, uint256 amount, MinAmountOutData memory minAmountOutData, address exchangeAddress)
        public
        returns (uint256)
    {
        console.log("Called Univ2");
        return _swap(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
    }

    function swapBal(address tokenIn, address tokenOut, uint256 amount, MinAmountOutData memory minAmountOutData, address exchangeAddress)
        public
        returns (uint256)
    {
        console.log("Called Bal");
        return _swap(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
    }

    function swapVelo(address tokenIn, address tokenOut, uint256 amount, MinAmountOutData memory minAmountOutData, address exchangeAddress)
        public
        returns (uint256)
    {
        console.log("Called Velo");
        return _swap(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
    }

    function swapUniV3(address tokenIn, address tokenOut, uint256 amount, MinAmountOutData memory minAmountOutData, address exchangeAddress)
        public
        returns (uint256)
    {
        console.log("Called Univ3");
        return _swap(tokenIn, tokenOut, amount, minAmountOutData, exchangeAddress);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amount, MinAmountOutData memory minAmountOutData, address exchangeAddress)
        private
        returns (uint256)
    {
        (address oraclePaymentToken, address oracleUnderlyingToken) = oracle.getTokens();
        require(tokenIn == address(oracleUnderlyingToken) || tokenIn == address(oraclePaymentToken), "Not allowed token in");
        require(tokenOut == address(oracleUnderlyingToken) || tokenOut == address(oraclePaymentToken), "Not allowed token");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
        console.log("Price from oracle is: %e", oracle.getPrice());
        uint256 amountToSend = (oracleUnderlyingToken == tokenIn) ? amount.mulWadUp(oracle.getPrice()) : (amount * 1e18) / oracle.getPrice();
        console.log("Amount to send is : %e", amountToSend);
        IERC20(tokenOut).transfer(msg.sender, amountToSend);
        return amountToSend;
    }
}
