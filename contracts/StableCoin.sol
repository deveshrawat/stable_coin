// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { ERC20 } from "./ERC20.sol";
import { DepositorCoin } from "./DepositorCoin.sol";
import { Oracle } from "./Oracle.sol";

contract StableCoin is ERC20 {
	DepositorCoin public depositorCoin;
	uint256 public feeRatePercentage;
	Oracle public oracle;
	uint256 public constant INITIAL_COLLATREAL_RATIO_PERCENTAGE = 10;

	constructor(uint256 _feeRatePercentage, Oracle _oracle) ERC20("StableCoin", "STC") {
		feeRatePercentage = _feeRatePercentage;
		oracle = _oracle;
	}

	function mint() external payable {
		uint256 fee = _getFee(msg.value);
		uint256 remainingEth = msg.value - fee;
		uint256 mintStableCoinAmount = remainingEth * oracle.getPrice();
		_mint(msg.sender, mintStableCoinAmount);
	}

	function burn(uint256 _burnStableCoinAmount) external {
		int256 currentDeficitOrSurplus = _getDificitOrSurplusInContractUsd();
		require(currentDeficitOrSurplus >= 0, "STC: can't burn with deficit");

		_burn(msg.sender, _burnStableCoinAmount);
		uint256 refundingEth = _burnStableCoinAmount / oracle.getPrice();
		uint256 fee = _getFee(refundingEth);
		uint256 remainingRefundingEth = refundingEth - fee;
		(bool success, ) = msg.sender.call{ value: remainingRefundingEth }("");
		require(success, "STC: Burn refund txn faiuled");
	}

	function _getFee(uint256 _ethAmount) private view returns (uint256 fee) {
		bool hasDepositors = address(depositorCoin) != address(0) && depositorCoin.totalSupply() > 0;
		if (!hasDepositors) {
			return 0;
		}
		return ((feeRatePercentage * _ethAmount) / 100);
	}

	function depositeCollateralBuffer() external payable {
		int256 deficitOrSurplusInUsd = _getDificitOrSurplusInContractUsd();
		if (deficitOrSurplusInUsd <= 0) {
			uint256 deficitInUsd = uint256(deficitOrSurplusInUsd * -1);
			uint256 usdInEthPrice = oracle.getPrice();
			uint256 deficitInEth = deficitInUsd / usdInEthPrice;
			uint256 requireInitialSurplusInUsd = (INITIAL_COLLATREAL_RATIO_PERCENTAGE * totalSupply) / 100;
			uint256 requireInitialSurplusInEth = requireInitialSurplusInUsd / usdInEthPrice;
			require(msg.value >= deficitInEth + requireInitialSurplusInEth, "STC: Initial collateral ratio not met!");
			uint256 newInitialSurplusInEth = msg.value - deficitInEth;
			uint256 newInitialSurplusInUsd = newInitialSurplusInEth * usdInEthPrice;
			depositorCoin = new DepositorCoin();
			uint256 mintDepositorAmount = newInitialSurplusInUsd;
			depositorCoin.mint(msg.sender, mintDepositorAmount);
			return;
		}
		uint256 surplusInUsd = uint256(deficitOrSurplusInUsd);
		uint256 dpcInUsdPrice = _getDPCInUsdPrice(surplusInUsd);
		uint256 mintDepositorCoinAmount = ((msg.value * dpcInUsdPrice) / oracle.getPrice());
		depositorCoin.mint(msg.sender, mintDepositorCoinAmount);
	}

	function withdrawCollateralBuffer(uint256 _burnDepositorCoinAmount) external {
		require(
			depositorCoin.balanceOf(msg.sender) >= _burnDepositorCoinAmount,
			"STC: sender has insufficient DPC funds"
		);

		depositorCoin.burn(msg.sender, _burnDepositorCoinAmount);
		int256 deficitOrSurplusInUsd = _getDificitOrSurplusInContractUsd();
		require(deficitOrSurplusInUsd > 0, "STC: no funds to withdraw");
		uint256 surplusInUsd = uint256(deficitOrSurplusInUsd);
		uint256 dpcInUsdPrice = _getDPCInUsdPrice(surplusInUsd);
		uint256 refundingUsd = _burnDepositorCoinAmount / dpcInUsdPrice;
		uint256 refundingEth = refundingUsd / oracle.getPrice();
		(bool success, ) = msg.sender.call{ value: refundingEth }("");
		require(success, "STC: refund transaction failed");
	}

	function _getDificitOrSurplusInContractUsd() private view returns (int256) {
		uint256 ethContractBalanceInUsd = (address(this).balance - msg.value) * oracle.getPrice();
		uint256 totalStableCoinBalanceInUsd = totalSupply;
		int256 deficitOrSurplus = int256(ethContractBalanceInUsd) - int256(totalStableCoinBalanceInUsd);
		return deficitOrSurplus;
	}

	function _getDPCInUsdPrice(uint256 _surplusInUsd) private view returns (uint256) {
		return depositorCoin.totalSupply() / _surplusInUsd;
	}
}
