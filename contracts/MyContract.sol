// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@thirdweb-dev/contracts/base/ERC721Base.sol";

contract UpgradedWillNFT is ERC721Base {
    struct WillDetails {
        address beneficiary;
        uint256 creationDate;
        uint256 executionDate;
        bool isExecuted;
        string assetHash; // Ensuring immutability of will metadata
    }

    mapping(uint256 => WillDetails) private _wills;
    mapping(uint256 => uint256) public lastProofOfLife;
    mapping(uint256 => address) public trustedContacts; // Emergency reset

    uint256 public constant PROOF_OF_LIFE_INTERVAL = 20 seconds;
    uint256 public constant CONTEST_PERIOD = 10 seconds;

    event WillCreated(uint256 indexed tokenId, address indexed owner, address beneficiary);
    event BeneficiaryUpdated(uint256 indexed tokenId, address newBeneficiary);
    event WillExecuted(uint256 indexed tokenId);
    event ProofOfLifeProvided(uint256 indexed tokenId, uint256 timestamp);
    event WillContested(uint256 indexed tokenId, address contestant);
    event EmergencyReset(uint256 indexed tokenId, address resetBy);

    error NotOwner();
    error WillExecutedAlready();
    error ProofOfLifeRequired();
    error InvalidTokenId();
    error ContestPeriodOver();
    error Unauthorized();

    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps
    ) ERC721Base(_defaultAdmin, _name, _symbol, _royaltyRecipient, _royaltyBps) {}

    // 🔹 Create a new will NFT
    function createWill(
        address _beneficiary,
        string memory _tokenURI,
        string memory _assetHash, // Hash of assets & metadata
        address _trustedContact
    ) external returns (uint256) {
        uint256 tokenId = totalSupply();
        mintTo(msg.sender, _tokenURI);

        _wills[tokenId] = WillDetails({
            beneficiary: _beneficiary,
            creationDate: block.timestamp,
            executionDate: 0,
            isExecuted: false,
            assetHash: _assetHash
        });

        lastProofOfLife[tokenId] = block.timestamp;
        trustedContacts[tokenId] = _trustedContact;

        emit WillCreated(tokenId, msg.sender, _beneficiary);
        return tokenId;
    }

    // 🔹 Update the beneficiary (only owner)
    function updateBeneficiary(uint256 tokenId, address newBeneficiary) external {
        WillDetails storage will = _getWill(tokenId);
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (will.isExecuted) revert WillExecutedAlready();

        will.beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(tokenId, newBeneficiary);
    }

    // 🔹 Execute will if proof of life is missing for 20 seconds
    function executeWill(uint256 tokenId) external {
        WillDetails storage will = _getWill(tokenId);

        require(
            block.timestamp > lastProofOfLife[tokenId] + PROOF_OF_LIFE_INTERVAL,
            "Proof of life still valid"
        );

        will.isExecuted = true;
        will.executionDate = block.timestamp;
        transferFrom(ownerOf(tokenId), will.beneficiary, tokenId);

        emit WillExecuted(tokenId);
    }

    // 🔹 Provide proof of life (Resets timer)
    function provideProofOfLife(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (_wills[tokenId].isExecuted) revert WillExecutedAlready();

        lastProofOfLife[tokenId] = block.timestamp;
        emit ProofOfLifeProvided(tokenId, block.timestamp);
    }

    // 🔹 Contest the execution within 10 seconds of being triggered
    function contestWill(uint256 tokenId) external {
        WillDetails storage will = _getWill(tokenId);
        if (block.timestamp > will.executionDate + CONTEST_PERIOD) revert ContestPeriodOver();

        will.isExecuted = false;
        emit WillContested(tokenId, msg.sender);
    }

    // 🔹 Emergency Reset by a trusted contact
    function emergencyReset(uint256 tokenId) external {
        if (trustedContacts[tokenId] != msg.sender) revert Unauthorized();

        lastProofOfLife[tokenId] = block.timestamp;
        emit EmergencyReset(tokenId, msg.sender);
    }

    // 🔹 Get will details
    function getWillDetails(uint256 tokenId) external view returns (WillDetails memory) {
        return _getWill(tokenId);
    }

    // 🔹 Internal helper function for validation
    function _getWill(uint256 tokenId) private view returns (WillDetails storage) {
        if (!_exists(tokenId)) revert InvalidTokenId();
        return _wills[tokenId];
    }
}
