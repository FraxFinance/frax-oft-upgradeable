pragma solidity ^0.8.0;

import "forge-std/console2.sol";

contract ConsoleMock {
    function log(string memory message) public pure {
        console2.log(message);
    }
}