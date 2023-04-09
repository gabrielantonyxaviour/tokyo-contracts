// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./interfaces/IMessageRecipient.sol";
import "./ERC721Promotion.sol";

contract Receiver is IMessageRecipient {
    mapping(address => address) public latestPromotionDeployment;
    mapping(address => address) public deploymentCreator;
    address public constant MAILBOX_ADDRESS =
        0xCC737a94FecaeC165AbCf12dED095BB13F037685;

    event PromotionNFTDeployed(address promotionNFTAddress);
    event TokenURIChanged(
        address contractAddress,
        address creator,
        string newURI
    );

    modifier onlyMailbox() {
        require(msg.sender == MAILBOX_ADDRESS);
        _;
    }

    function handle(
        uint32,
        bytes32,
        bytes calldata _body
    ) external onlyMailbox {
        (
            string memory _name,
            string memory _symbol,
            string memory _badgeURI,
            address _promoterAddress,
            uint _claimsPerPerson,
            bytes32 _salt
        ) = abi.decode(_body, (string, string, string, address, uint, bytes32));
        ERC721Promotion promotion = (new ERC721Promotion){salt: _salt}(
            _name,
            _symbol,
            _badgeURI,
            _promoterAddress,
            _claimsPerPerson
        );
        emit PromotionNFTDeployed(address(promotion));
    }

    function changeTokenURI(address contractAddress, string calldata newURI)
        public
    {
        require(msg.sender == deploymentCreator[contractAddress], "Not owned");
        ERC721Promotion(contractAddress).setTokenURI(newURI);

        emit TokenURIChanged(contractAddress, msg.sender, newURI);
    }

    function getLatestPromotionDeployment(address promoter)
        public
        view
        returns (address)
    {
        return latestPromotionDeployment[promoter];
    }

    function bytes32ToString(bytes32 _bytes32)
        public
        pure
        returns (string memory)
    {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
