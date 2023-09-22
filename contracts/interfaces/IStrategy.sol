// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IStrategy {
    function burn(
        uint256 share,
        uint256 amount0Min,
        uint256 amount1Min
    ) 
        external 
        returns (
            uint256 collect0, 
            uint256 collect1
        );
    function getAUMWithFees(
        bool includeFee
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 totalFee0,
            uint256 totalFee1
        );
    function pool() external view returns (IUniswapV3Pool);
    function claimFee() external;
    function balanceOf(address account) external view returns (uint256);
}