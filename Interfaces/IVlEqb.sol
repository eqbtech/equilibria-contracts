// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IVlEqb {
    function lock(address _user, uint256 _amount, uint256 _weeks) external;
}
