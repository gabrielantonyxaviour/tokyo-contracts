// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IMessageRecipient.sol";

contract ZaisanTokenNFT is
    ERC721,
    ERC721URIStorage,
    Ownable,
    IMessageRecipient
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    string public badgeTokenURI;
    uint256 public amountOfClaimsPerPerson;
    mapping(address => uint) claimerToClaimsCount;
    address public constant MAILBOX_ADDRESS =
        0xCC737a94FecaeC165AbCf12dED095BB13F037685;
    address public promoter;

    event ClaimedPromotion(address claimer, uint claimCount);

    constructor(
        string memory _tokenURI,
        address _promoterAddress,
        uint _amountOfClaimsPerPerson
    ) ERC721("ZaisaNFT", "ZFT") {
        badgeTokenURI = _tokenURI;
        amountOfClaimsPerPerson = _amountOfClaimsPerPerson;
        promoter = _promoterAddress;
    }

    modifier onlyMailbox() {
        require(msg.sender == MAILBOX_ADDRESS);
        _;
    }

    function handle(
        uint32,
        bytes32,
        bytes calldata _body
    ) external onlyMailbox {
        address claimer = abi.decode(_body, (address));
        if (claimerToClaimsCount[claimer] == 0) {
            safeMint(claimer);
        } else {
            require(
                claimerToClaimsCount[claimer] < amountOfClaimsPerPerson,
                "No more claims"
            );
            addClaim(claimer);
        }
    }

    function safeMint(address to) internal {
        require(claimerToClaimsCount[to] == 0, "Already owns NFT");
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, badgeTokenURI);
        claimerToClaimsCount[to] = 1;
        emit ClaimedPromotion(to, 1);
    }

    function addClaim(address to) internal {
        claimerToClaimsCount[to] += 1;

        emit ClaimedPromotion(to, claimerToClaimsCount[to]);
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        badgeTokenURI = _tokenURI;
    }

    // Soulbound Token
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override {
        revert("Cannot transfer");
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256) internal pure override(ERC721, ERC721URIStorage) {
        revert("Disabled");
        // super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
