// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ZaisanSismoNFT is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    string public badgeTokenURI;
    address public promoter;

    event ClaimedPromotion(address claimer, uint claimCount);

    constructor(string memory _tokenURI, address _promoterAddress)
        ERC721("ZaisaNFT", "ZFT")
    {
        badgeTokenURI = _tokenURI;
        promoter = _promoterAddress;
    }

    function claim(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, badgeTokenURI);
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        require(msg.sender == promoter, "Unauthorized");
        badgeTokenURI = _tokenURI;
    }

    // Soulbound Token
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override {
        revert("Disabled");
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
