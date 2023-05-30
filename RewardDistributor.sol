// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";
import "./Dependencies/Errors.sol";

contract RewardDistributor is AccessControlUpgradeable {
    using TransferHelper for address;
    using TransferHelper for IERC20;

    address public token;

    bytes32 public merkleRoot;

    mapping(address => uint256) public claimedAmounts;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event MerkleRootUpdatedAndFunded(bytes32 _merkleRoot, uint256 _amount);
    event Claimed(address _user, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token) public initializer {
        __AccessControl_init();

        token = _token;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setMerkleRootAndFund(
        bytes32 _merkleRoot,
        uint256 _amount
    ) external payable onlyRole(ADMIN_ROLE) {
        if (AddressLib.isPlatformToken(token)) {
            require(_amount == msg.value, "invalid amount");
        } else {
            require(msg.value == 0, "invalid msg.value");
            IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        merkleRoot = _merkleRoot;

        emit MerkleRootUpdatedAndFunded(_merkleRoot, _amount);
    }

    function claim(
        uint256 _amount,
        bytes32[] calldata _proof
    ) external returns (uint256 amountOut) {
        if (!_verifyMerkleData(msg.sender, _amount, _proof)) {
            revert Errors.InvalidMerkleProof();
        }

        amountOut = _amount - claimedAmounts[msg.sender];

        require(amountOut > 0, "nothing to claim");

        claimedAmounts[msg.sender] = _amount;

        token.safeTransferToken(msg.sender, amountOut);
        emit Claimed(msg.sender, amountOut);
    }

    function _verifyMerkleData(
        address _user,
        uint256 _amount,
        bytes32[] calldata _proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(_user, _amount)))
        );
        return MerkleProof.verify(_proof, merkleRoot, leaf);
    }
}
