// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@shared/lib-contracts-v0.8/contracts/Dependencies/TransferHelper.sol";
import "./Dependencies/Errors.sol";

contract BribeManager is AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using TransferHelper for address;

    struct BribeInfo {
        address pool;
        address[] rewardTokens;
        uint256[] rewardAmounts;
        bytes32 merkleRoot;
    }

    mapping(uint256 => BribeInfo[]) public bribes;

    mapping(uint256 => mapping(uint256 => mapping(address => bool)))
        public hasClaimed;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant THIRD_PARTY_ROLE = keccak256("THIRD_PARTY_ROLE");

    event BribeCreated(
        uint256 _weekNo,
        address indexed _pool,
        address[] _rewardTokens,
        uint256[] _rewardAmounts
    );
    event BribeEnded(
        uint256 _weekNo,
        address indexed _pool,
        bytes32 _merkleRoot
    );
    event Claimed(
        address indexed _user,
        uint256 _weekNo,
        address indexed _pool,
        uint256[] _rewardAmounts
    );
    event RewardAmountsAdded(
        address indexed _caller,
        uint256 _weekNo,
        address indexed _pool,
        uint256[] _rewardTokenIndexs,
        uint256[] _rewardAmounts
    );
    event AdminWithdrawn(address indexed _token, uint256 _amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function getBribesLength(uint256 _weekNo) external view returns (uint256) {
        return bribes[_weekNo].length;
    }

    function getBribe(
        uint256 _weekNo,
        uint256 _index
    ) external view returns (BribeInfo memory) {
        return bribes[_weekNo][_index];
    }

    function getBribes(
        uint256 _weekNo
    ) external view returns (BribeInfo[] memory) {
        return bribes[_weekNo];
    }

    function createBribe(
        uint256 _weekNo,
        address _pool,
        address[] calldata _rewardTokens,
        uint256[] calldata _rewardAmounts
    ) public onlyRole(ADMIN_ROLE) {
        require(_pool != address(0), "invalid _pool");
        for (uint256 i = 0; i < bribes[_weekNo].length; i++) {
            require(
                bribes[_weekNo][i].pool != _pool,
                "bribe for this pool already exists"
            );
        }
        require(_rewardTokens.length > 0, "invalid _rewardTokens");

        if (_rewardAmounts.length == 0) {
            bribes[_weekNo].push(
                BribeInfo({
                    pool: _pool,
                    rewardTokens: _rewardTokens,
                    rewardAmounts: new uint256[](_rewardTokens.length),
                    merkleRoot: bytes32(0)
                })
            );
        } else {
            require(
                _rewardTokens.length == _rewardAmounts.length,
                "invalid _rewardTokens or _rewardAmounts"
            );
            for (uint256 i = 0; i < _rewardAmounts.length; i++) {
                require(_rewardAmounts[i] > 0, "invalid _rewardAmounts");
            }

            bribes[_weekNo].push(
                BribeInfo({
                    pool: _pool,
                    rewardTokens: _rewardTokens,
                    rewardAmounts: _rewardAmounts,
                    merkleRoot: bytes32(0)
                })
            );
        }

        emit BribeCreated(_weekNo, _pool, _rewardTokens, _rewardAmounts);
    }

    function addRewardAmounts(
        uint256 _weekNo,
        uint256 _index,
        uint256[] calldata _rewardTokenIndexs,
        uint256[] calldata _rewardAmounts
    ) external payable onlyRole(THIRD_PARTY_ROLE) {
        BribeInfo storage bribe = bribes[_weekNo][_index];
        require(bribe.pool != address(0), "invalid bribe");
        require(bribe.merkleRoot == bytes32(0), "bribe already ended");
        require(
            _rewardTokenIndexs.length == _rewardAmounts.length &&
                _rewardTokenIndexs.length > 0,
            "invalid _rewardTokenIndexs or _rewardAmounts"
        );

        uint256 ethAmount = 0;
        for (uint256 i = 0; i < _rewardTokenIndexs.length; i++) {
            uint256 index = _rewardTokenIndexs[i];
            require(
                index < bribe.rewardTokens.length,
                "invalid _rewardTokenIndexs"
            );
            address token = bribe.rewardTokens[index];
            if (AddressLib.isPlatformToken(token)) {
                ethAmount += _rewardAmounts[i];
            } else {
                IERC20(token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _rewardAmounts[i]
                );
            }

            bribe.rewardAmounts[index] += _rewardAmounts[i];
        }

        if (ethAmount > 0) {
            require(ethAmount == msg.value, "invalid msg.value");
        }

        emit RewardAmountsAdded(
            msg.sender,
            _weekNo,
            bribe.pool,
            _rewardTokenIndexs,
            _rewardAmounts
        );
    }

    function batchCreateBribe(
        uint256 _weekNo,
        address[] calldata _pool,
        address[][] calldata _rewardTokens,
        uint256[][] calldata _rewardAmounts
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _pool.length; i++) {
            createBribe(_weekNo, _pool[i], _rewardTokens[i], _rewardAmounts[i]);
        }
    }

    function _endBribe(
        uint256 _weekNo,
        uint256 _index,
        bytes32 _merkleRoot,
        bool _skipTransfer
    ) internal returns (uint256 totalNativeAmount) {
        require(_merkleRoot != bytes32(0), "invalid _merkleRoot");
        BribeInfo storage bribe = bribes[_weekNo][_index];
        require(bribe.pool != address(0), "invalid bribe");
        require(bribe.merkleRoot == bytes32(0), "bribe already ended");

        if (!_skipTransfer) {
            for (uint256 i = 0; i < bribe.rewardTokens.length; i++) {
                address token = bribe.rewardTokens[i];
                uint256 amount = bribe.rewardAmounts[i];
                if (AddressLib.isPlatformToken(token)) {
                    totalNativeAmount += amount;
                } else {
                    IERC20(token).safeTransferFrom(
                        msg.sender,
                        address(this),
                        amount
                    );
                }
            }
        }

        bribe.merkleRoot = _merkleRoot;

        emit BribeEnded(_weekNo, bribe.pool, _merkleRoot);
    }

    function endBribe(
        uint256 _weekNo,
        uint256 _index,
        bytes32 _merkleRoot,
        bool _skipTransfer
    ) public payable onlyRole(ADMIN_ROLE) {
        uint256 totalNativeAmount = _endBribe(
            _weekNo,
            _index,
            _merkleRoot,
            _skipTransfer
        );
        require(totalNativeAmount == msg.value, "invalid msg.value");
    }

    function batchEndBribe(
        uint256 _weekNo,
        uint256[] calldata _index,
        bytes32[] calldata _merkleRoot,
        bool _skipTransfer
    ) external payable onlyRole(ADMIN_ROLE) {
        uint256 totalNativeAmount;
        for (uint256 i = 0; i < _index.length; i++) {
            totalNativeAmount += _endBribe(
                _weekNo,
                _index[i],
                _merkleRoot[i],
                _skipTransfer
            );
        }
        require(totalNativeAmount == msg.value, "invalid msg.value");
    }

    function claim(
        uint256 _weekNo,
        uint256 _index,
        uint256[] calldata _amounts,
        bytes32[] calldata _proof
    ) public {
        BribeInfo memory bribe = bribes[_weekNo][_index];
        require(bribe.pool != address(0), "invalid bribe");
        require(bribe.merkleRoot != bytes32(0), "bribe not ended");
        require(!hasClaimed[_weekNo][_index][msg.sender], "already claimed");

        if (
            !_verifyMerkleData(bribe.merkleRoot, msg.sender, _amounts, _proof)
        ) {
            revert Errors.InvalidMerkleProof();
        }

        hasClaimed[_weekNo][_index][msg.sender] = true;

        for (uint256 i = 0; i < bribe.rewardTokens.length; i++) {
            address token = bribe.rewardTokens[i];
            uint256 amount = _amounts[i];
            token.safeTransferToken(msg.sender, amount);
        }

        emit Claimed(msg.sender, _weekNo, bribe.pool, _amounts);
    }

    function batchClaim(
        uint256[] calldata _weekNo,
        uint256[][] calldata _index,
        uint256[][][] calldata _amounts,
        bytes32[][][] calldata _proof
    ) external {
        for (uint256 i = 0; i < _weekNo.length; i++) {
            for (uint256 j = 0; j < _index[i].length; j++) {
                claim(_weekNo[i], _index[i][j], _amounts[i][j], _proof[i][j]);
            }
        }
    }

    function adminWithdraw(
        address _token,
        uint256 _amount
    ) external onlyRole(ADMIN_ROLE) {
        TransferHelper.safeTransferToken(_token, msg.sender, _amount);

        emit AdminWithdrawn(_token, _amount);
    }

    function _verifyMerkleData(
        bytes32 _merkleRoot,
        address _user,
        uint256[] calldata _amounts,
        bytes32[] calldata _proof
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(_user, _amounts)))
        );
        return MerkleProof.verify(_proof, _merkleRoot, leaf);
    }
}
