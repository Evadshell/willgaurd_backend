// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@thirdweb-dev/contracts/base/ERC721Base.sol";

contract MyContract is ERC721Base {
    struct WillDetails {
        address beneficiary;
        uint256 creationDate;
        uint256 executionDate;
        bool isExecuted;
        string[] assetURIs;
    }

    mapping(uint256 => WillDetails) private _wills;
    mapping(uint256 => uint256) public lastProofOfLife;
    uint256 public constant PROOF_OF_LIFE_INTERVAL = 365 days;

    event WillCreated(uint256 indexed tokenId, address indexed owner, address beneficiary);
    event BeneficiaryUpdated(uint256 indexed tokenId, address newBeneficiary);
    event WillExecuted(uint256 indexed tokenId);
    event ProofOfLifeProvided(uint256 indexed tokenId, uint256 timestamp);

    error NotOwner();
    error WillExecutedAlready();
    error ProofOfLifeRequired();
    error InvalidTokenId();

    constructor(
         address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps
        // address _primarySaleRecipient
    ) ERC721Base(_defaultAdmin,_name, _symbol, _royaltyRecipient, _royaltyBps) {}

    // Create will with metadata and beneficiary
    function createWill(
        address _beneficiary,
        string memory _tokenURI,
        string[] memory _assetURIs
    ) external returns (uint256) {
        uint256 tokenId = totalSupply();
        
        mintTo(msg.sender, _tokenURI);
        
        _wills[tokenId] = WillDetails({
            beneficiary: _beneficiary,
            creationDate: block.timestamp,
            executionDate: 0,
            isExecuted: false,
            assetURIs: _assetURIs
        });

        lastProofOfLife[tokenId] = block.timestamp;
        emit WillCreated(tokenId, msg.sender, _beneficiary);
        return tokenId;
    }

    // Update beneficiary (owner only)
    function updateBeneficiary(uint256 tokenId, address newBeneficiary) external {
        WillDetails storage will = _getWill(tokenId);
        
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (will.isExecuted) revert WillExecutedAlready();
        
        will.beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(tokenId, newBeneficiary);
    }

    // Execute will if no proof of life in 1 year
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

    // Reset proof of life timer
    function provideProofOfLife(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (_wills[tokenId].isExecuted) revert WillExecutedAlready();
        
        lastProofOfLife[tokenId] = block.timestamp;
        emit ProofOfLifeProvided(tokenId, block.timestamp);
    }

    // Get will details
    function getWillDetails(uint256 tokenId) external view returns (WillDetails memory) {
        return _getWill(tokenId);
    }

    // Helper function with validation
    function _getWill(uint256 tokenId) private view returns (WillDetails storage) {
        if (!_exists(tokenId)) revert InvalidTokenId();
        return _wills[tokenId];
    }
}