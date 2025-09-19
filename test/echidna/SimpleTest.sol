// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title SimpleTest
 * @notice Basic Echidna test to verify the setup works
 */
contract SimpleTest {
    uint public value;

    function setValue(uint _value) public {
        value = _value;
    }

    // Property: value should never exceed 1000
    function echidna_value_under_1000() public view returns (bool) {
        return value < 1000;
    }
}
