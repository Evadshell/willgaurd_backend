// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@thirdweb-dev/contracts/base/ERC721Base.sol";

contract UpgradedWillNFT is ERC721Base {
    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps
    ) ERC721Base(_defaultAdmin, _name, _symbol, _royaltyRecipient, _royaltyBps) {}

    struct WillDetails {
        address beneficiary;
        address[] secondaryBeneficiaries;
        uint256 creationDate;
        uint256 executionDate;
        bool isExecuted;
        string assetHash;
        bytes32 encryptedKey;
        uint256 version;
    }

    struct PendingChange {
        address newBeneficiary;
        uint256 unlockTime;
    }

    mapping(uint256 => WillDetails) private _wills;
    mapping(uint256 => address[]) public guardians;
    mapping(uint256 => mapping(address => bool)) public guardianApprovals;
    mapping(uint256 => PendingChange) public pendingChanges;
    mapping(uint256 => uint256) public lastActivity;

    uint256 public constant PROOF_OF_LIFE_INTERVAL = 7 days;
    uint256 public constant CONTEST_PERIOD = 3 days;
    uint256 public constant CHANGE_DELAY = 2 days;

    event WillCreated(uint256 indexed tokenId, address indexed owner, address beneficiary);
    event WillUpdated(uint256 indexed tokenId, uint256 version);
    event InheritanceUnlocked(uint256 indexed tokenId);
    event MultiSigApproval(uint256 indexed tokenId, address guardian);
    
    error ChangePending();
    error InsufficientApprovals();

    function createWill(
        uint256 tokenId,
        address _beneficiary,
        string memory _assetHash,
        bytes32 _encryptedKey,
        address[] calldata _guardians
    ) external {
        require(!_exists(tokenId), "Token already exists");
        _mint(msg.sender, tokenId);
        
        _wills[tokenId] = WillDetails({
            beneficiary: _beneficiary,
            secondaryBeneficiaries: new address[](0),
            creationDate: block.timestamp,
            executionDate: 0,
            isExecuted: false,
            assetHash: _assetHash,
            encryptedKey: _encryptedKey,
            version: 1
        });
        
        guardians[tokenId] = _guardians;
        lastActivity[tokenId] = block.timestamp;
        emit WillCreated(tokenId, msg.sender, _beneficiary);
    }

    function provideProofOfLife(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        lastActivity[tokenId] = block.timestamp;
    }

    function requestBeneficiaryChange(uint256 tokenId, address _newBeneficiary) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        pendingChanges[tokenId] = PendingChange(_newBeneficiary, block.timestamp + CHANGE_DELAY);
    }

    function confirmBeneficiaryChange(uint256 tokenId) external {
        PendingChange memory change = pendingChanges[tokenId];
        require(block.timestamp >= change.unlockTime, "Too early");
        require(checkGuardianApprovals(tokenId), "Need guardian approval");

        _wills[tokenId].beneficiary = change.newBeneficiary;
        _wills[tokenId].version++;
        delete pendingChanges[tokenId];
        emit WillUpdated(tokenId, _wills[tokenId].version);
    }

    function approveChange(uint256 tokenId) external {
        require(isGuardian(tokenId, msg.sender), "Not guardian");
        guardianApprovals[tokenId][msg.sender] = true;
        emit MultiSigApproval(tokenId, msg.sender);
    }

    function executeWill(uint256 tokenId) external {
        require(block.timestamp > lastActivity[tokenId] + PROOF_OF_LIFE_INTERVAL, "Owner still active");
        require(!_wills[tokenId].isExecuted, "Already executed");
        require(msg.sender == _wills[tokenId].beneficiary, "Not beneficiary");
        
        _wills[tokenId].isExecuted = true;
        _wills[tokenId].executionDate = block.timestamp;
        emit InheritanceUnlocked(tokenId);
    }

    function isGuardian(uint256 tokenId, address _address) internal view returns (bool) {
        address[] memory _guardians = guardians[tokenId];
        for (uint256 i = 0; i < _guardians.length; i++) {
            if (_guardians[i] == _address) return true;
        }
        return false;
    }

    function checkGuardianApprovals(uint256 tokenId) internal view returns (bool) {
        address[] memory _guardians = guardians[tokenId];
        uint256 approvals;
        for (uint256 i = 0; i < _guardians.length; i++) {
            if (guardianApprovals[tokenId][_guardians[i]]) approvals++;
        }
        return approvals >= (_guardians.length / 2) + 1;
    }
}
