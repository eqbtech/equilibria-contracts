// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "./Interfaces/IEquibiliaToken.sol";

contract EquibiliaToken is
    IEquibiliaToken,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    mapping(address => bool) public access;

    uint256 public maxSupply;
    uint256 public totalCliffs;
    uint256 public reductionPerCliff;

    uint256 public constant FACTOR_DENOMINATOR = 10000;
    uint256 public factor;

    // --- Events ---
    event AccessUpdated(address _operator, bool _access);

    function initialize() public initializer {
        __Ownable_init();

        __ERC20_init_unchained("Equibilia Token", "EQB");

        access[msg.sender] = true;

        maxSupply = 1e27; // 1e27 = 1e9 * 1e18, 1B
        totalCliffs = 1000;
        reductionPerCliff = maxSupply / totalCliffs;

        emit AccessUpdated(msg.sender, true);
    }

    function setAccess(address _operator, bool _access) external onlyOwner {
        require(_operator != address(0), "invalid _operator!");
        access[_operator] = _access;

        emit AccessUpdated(_operator, _access);
    }

    function setFactor(uint256 _factor) external onlyOwner {
        factor = _factor;
    }

    function mint(address _to, uint256 _amount) external override {
        require(access[msg.sender], "!auth");

        uint256 supply = totalSupply();
        if (supply == 0) {
            //premine, one time only
            _mint(_to, _amount);
            return;
        }

        //use current supply to gauge cliff
        //this will cause a bit of overflow into the next cliff range
        //but should be within reasonable levels.
        //requires a max supply check though
        uint256 cliff = supply / reductionPerCliff;
        //mint if below total cliffs
        if (cliff < totalCliffs) {
            //for reduction% take inverse of current cliff
            uint256 reduction = totalCliffs - cliff;
            //reduce
            _amount = (_amount * reduction) / totalCliffs;
            _amount = factor == 0
                ? _amount
                : (_amount * factor) / FACTOR_DENOMINATOR;

            //supply cap check
            uint256 amtTillMax = maxSupply - supply;
            if (_amount > amtTillMax) {
                _amount = amtTillMax;
            }

            //mint
            _mint(_to, _amount);
        }
    }
}
