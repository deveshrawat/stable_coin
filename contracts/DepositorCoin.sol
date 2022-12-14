// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { ERC20 } from "./ERC20.sol";

contract DepositorCoin is ERC20 {
	address public owner;

	constructor() ERC20("DepositorCoin", "DPC") {
		owner = msg.sender;
	}

	function mint(address _to, uint256 _amount) external {
		require(msg.sender == owner, "DPC: Only owner can mint");
		_mint(_to, _amount);
	}

	function burn(address _from, uint256 _amount) external {
		require(msg.sender == owner, "DPC: Only owner can burn");
		_burn(_from, _amount);
	}
}
