// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@thirdweb-dev/contracts/base/ERC721Base.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract InheritanceWill is ERC721Base, ReentrancyGuard {
    // 1. Enhanced State Variables
    struct WillDetails {
        address beneficiary;
        uint256 creationDate;
        uint256 executionDate;
        bool isExecuted;
        string[] assetURIs;
        uint256 proofInterval;
        uint256 contestPeriodEnd;
        address[] confirmations;
        mapping(address => bool) arbiters;
        uint256 arbiterCount;
    }
    
    
    // 2. Demo-Friendly Configuration
    uint256 public constant DEMO_INTERVAL = 30;
    uint256 public constant CONTEST_PERIOD = 5 minutes;
    
    // 3. Multi-Asset Support
    mapping(uint256 => address[]) public lockedERC20s;
    mapping(uint256 => uint256) public lockedETH;
    mapping(uint256 => mapping(address => uint256)) public erc20Balances;
    
    // 4. Oracle Integration
    AggregatorV3Interface internal proofOfLifeOracle;
    address public oracleAddress;

    // Mapping to store will details for each tokenId
    mapping(uint256 => WillDetails) private _wills;
    
    // Mapping to store the last proof of life timestamp for each tokenId
    mapping(uint256 => uint256) private lastProofOfLife;
    
    // 5. Events
    event WillContested(uint256 indexed tokenId, address contestant);
    event AssetLocked(uint256 indexed tokenId, address asset, uint256 amount);
    event MultiSigConfirmed(uint256 indexed tokenId, address confirmer);

    error InvalidContestPeriod();
    error InsufficientConfirmations();
    error AssetTransferFailed();
    
    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _oracle
    ) ERC721Base(_defaultAdmin, _name, _symbol, _royaltyRecipient, _royaltyBps) {
        proofOfLifeOracle = AggregatorV3Interface(_oracle);
        oracleAddress = _oracle;
    }

    // 6. Enhanced Will Creation with Multi-Asset Locking
    function createWill(
        address _beneficiary,
        string memory _tokenURI,
        string[] memory _assetURIs,
        address[] calldata _arbiters,
        address[] calldata _erc20s,
        uint256[] calldata _amounts
    ) external payable nonReentrant returns (uint256) {
        uint256 tokenId = totalSupply();
        mintTo(msg.sender, _tokenURI);
        
        WillDetails storage will = _wills[tokenId];
        will.beneficiary = _beneficiary;
        will.proofInterval = DEMO_INTERVAL;
        will.creationDate = block.timestamp;
        will.assetURIs = _assetURIs;
        
        // Lock assets
        for(uint256 i = 0; i < _erc20s.length; i++) {
            IERC20(_erc20s[i]).transferFrom(msg.sender, address(this), _amounts[i]);
            erc20Balances[tokenId][_erc20s[i]] += _amounts[i];
            emit AssetLocked(tokenId, _erc20s[i], _amounts[i]);
        }
        
        lockedETH[tokenId] = msg.value;
        emit AssetLocked(tokenId, address(0), msg.value);

        // Setup arbiters
        for(uint256 i = 0; i < _arbiters.length; i++) {
            will.arbiters[_arbiters[i]] = true;
        }

        return tokenId;
    }

    // 7. Multi-Sig Execution with Oracle Check
    function _getWill(uint256 tokenId) private view returns (WillDetails storage) {
        return _wills[tokenId];
    }
    function executeWill(uint256 tokenId) external nonReentrant {
        WillDetails storage will = _getWill(tokenId);
        
        require(
            block.timestamp > lastProofOfLife[tokenId] + will.proofInterval,
            "Proof of life valid"
        );
        if(will.confirmations.length < (will.arbiterCount * 2) / 3) {
        // Require 2/3 arbiters confirm
        if(will.confirmations.length < (will.arbiterCount * 2) / 3) {
            revert InsufficientConfirmations();
        }

        // Chainlink Oracle simulation for demo
        (, int256 oracleResponse,,,) = proofOfLifeOracle.latestRoundData();
        require(oracleResponse > 0, "Oracle verification failed");

        _transferAssets(tokenId);
        will.isExecuted = true;
        will.executionDate = block.timestamp;
        will.contestPeriodEnd = block.timestamp + CONTEST_PERIOD;
    }}

    // 8. Time-Locked Asset Release
    function _transferAssets(uint256 tokenId) private {
        WillDetails storage will = _getWill(tokenId);
        
        // Transfer ERC20s
        for(uint256 i = 0; i < lockedERC20s[tokenId].length; i++) {
            address token = lockedERC20s[tokenId][i];
            uint256 amount = erc20Balances[tokenId][token];
            IERC20(token).transfer(will.beneficiary, amount);
        }
        
        // Transfer ETH
        (bool success,) = will.beneficiary.call{value: lockedETH[tokenId]}("");
        if(!success) revert AssetTransferFailed();
    }

    // 9. Contest Mechanism
    function contestWill(uint256 tokenId) external {
        WillDetails storage will = _getWill(tokenId);
        if(block.timestamp > will.contestPeriodEnd) revert InvalidContestPeriod();
        
        will.isExecuted = false;
        emit WillContested(tokenId, msg.sender);
    }

    // 10. Demo Helpers
    function simulateOracleResponse(int256 value) external {
        // For demo purposes only - remove in production
        (bool success,) = oracleAddress.call(
            abi.encodeWithSignature("setResponse(int256)", value)
        );
        require(success, "Simulation failed");
    }
}
