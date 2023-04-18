// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "../library/access/Ownable.sol";
import "../library/utils/Address.sol";
import "../library/security/ReentrancyGuard.sol";
import "../library/token/ERC20/IERC20.sol";
import "../library/token/ERC20/utils/SafeERC20.sol";


contract LionDEXRewardVault is Ownable,ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    mapping(address => bool) private lionDexPoolMap;

    event WithdrawETH(address indexed to, uint256 value);
    event SetLionDexPool(address poolAddr,bool active);
    event WithdrawToken(
        IERC20 indexed token,
        address indexed to,
        uint256 value
    );

    modifier onlyLionDexPool() {
        require(isLionDexPool(msg.sender), "LionDEXRewardVault: not keeper");
        _;
    }

    function withdrawEth(uint256 _amount) public onlyLionDexPool nonReentrant{
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "LionDEXRewardVault: Failed to withdraw Ether");
        emit WithdrawETH(msg.sender,_amount);
    }

    function withdrawToken(IERC20 _token,uint256 _amount) public onlyLionDexPool nonReentrant{
        _token.safeTransfer(msg.sender, _amount);
        emit WithdrawToken(_token, msg.sender, _amount);
    }

    function setLionDexPool(address addr, bool active) public onlyOwner {
        require(
            addr.isContract(),
            "LionDEXRewardVault: address must be eth pool contract"
        );
        lionDexPoolMap[addr] = active;
        emit SetLionDexPool(addr,active);
    }

    function isLionDexPool(address addr) public view returns (bool) {
        return lionDexPoolMap[addr];
    }

    function ethBalance() public view returns (uint256) {
        return address(this).balance;
    }


    receive() external payable {}
}
