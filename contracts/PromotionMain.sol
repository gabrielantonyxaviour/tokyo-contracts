// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/IInterchainQueryRouter.sol";
import "./interfaces/IMailbox.sol";
import "./interfaces/IInterchainGasPaymaster.sol";
import "./interfaces/IReceiver.sol";
import "./ERC721Promotion.sol";

contract PromotionMain is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    struct Receiver {
        bytes32 destinationReceiverAddress;
        bool isExists;
    }

    struct Promotion {
        address promotionAddress;
        uint32 destinationDomain;
        address creator;
        uint createdAt;
        uint claimsPerPerson;
        bool isExists;
    }

    struct Claim {
        uint32 destinationDomain;
        address promotionAddress;
        uint claimsCount;
        bool isExists;
    }

    mapping(bytes32 => Promotion) public promotions; // Promotion Id => Promotion
    mapping(bytes32 => mapping(address => Claim)) public claims;

    mapping(bytes32 => uint256) public gasTank;
    mapping(uint32 => Receiver) public chains;

    IMailbox public constant mailbox =
        IMailbox(0xCC737a94FecaeC165AbCf12dED095BB13F037685);
    IInterchainGasPaymaster public constant igp =
        IInterchainGasPaymaster(0xF90cB82a76492614D07B82a7658917f3aC811Ac1);
    IInterchainQueryRouter public constant iqsRouter =
        IInterchainQueryRouter(0xF782C6C4A02f2c71BB8a1Db0166FAB40ea956818);

    event NewChainAdded(uint32 destinationDomain);
    event GasTankFilled(bytes32 promotionId, uint256 amount);
    event GasTankRefunded(bytes32 promotionId, uint256 amount);
    event PromotionCreated(
        bytes32 promotionId,
        address promotionAddress,
        uint32 destinationDomain,
        address creator,
        uint createdAt,
        uint claimsPerPerson,
        string badgeURI
    );
    event ClaimedPromotion(
        bytes32 promotionId,
        address promotionAddress,
        address claimer,
        uint32 destinationDomain,
        uint claimsCount,
        uint claimedAt
    );

    function addChain(uint32 destinationDomain, address destinationReceiver)
        public
        onlyOwner
    {
        chains[destinationDomain] = Receiver(
            addressToBytes32(destinationReceiver),
            true
        );
    }

    function _getAddress(
        string memory name,
        string memory symbol,
        uint32 destinationDomain,
        uint claimsPerPerson,
        string memory badgeURI,
        uint _salt
    ) internal view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(ERC721Promotion).creationCode,
            abi.encode(name, symbol, badgeURI, msg.sender, claimsPerPerson)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                chains[destinationDomain].destinationReceiverAddress,
                bytes32(_salt),
                keccak256(bytecode)
            )
        );

        return address(uint160(uint(hash)));
    }

    function createPromotion(
        string memory name,
        string memory symbol,
        uint32 destinationDomain,
        uint claimsPerPerson,
        string memory badgeURI,
        uint _salt,
        uint gasAmount
    ) public payable {
        require(chains[destinationDomain].isExists, "Invalid Destination");
        // 1. Create PromotionNFT contract in destination chain and Fill Gas
        bytes memory message = abi.encode(
            name,
            symbol,
            badgeURI,
            msg.sender,
            claimsPerPerson,
            bytes32(_salt)
        );

        bytes32 messageId = mailbox.dispatch(
            destinationDomain,
            chains[destinationDomain].destinationReceiverAddress,
            message
        );
        address _promotionAddress = _getAddress(
            name,
            symbol,
            destinationDomain,
            claimsPerPerson,
            badgeURI,
            _salt
        );
        bytes32 _promotionId = keccak256(
            abi.encodePacked(
                name,
                symbol,
                _promotionAddress,
                destinationDomain,
                claimsPerPerson,
                badgeURI,
                msg.sender,
                block.timestamp
            )
        );
        require(promotions[_promotionId].isExists == false, "Promotion exists");

        // 2. Get gas amount
        uint256 quotedPayment = getQuotedPayment(destinationDomain, gasAmount);
        require(msg.value >= quotedPayment, "Insufficient gas");
        gasTank[_promotionId] += (msg.value - quotedPayment);

        // 3. Pay for Interchain Gas
        igp.payForGas{value: quotedPayment}(
            messageId,
            destinationDomain,
            gasAmount,
            msg.sender
        );

        // 4. Update State Variables
        promotions[_promotionId] = Promotion(
            _promotionAddress,
            destinationDomain,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            true
        );

        // 5. Emit events
        if (gasTank[_promotionId] > 0) {
            emit GasTankFilled(_promotionId, gasTank[_promotionId]);
        }
        emit PromotionCreated(
            _promotionId,
            _promotionAddress,
            destinationDomain,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            badgeURI
        );
    }

    function claimPromotion(
        bytes32 _promotionId,
        uint32 destinationDomain,
        bytes calldata signature,
        address claimer,
        uint gasAmount
    ) public {
        require(chains[destinationDomain].isExists, "Invalid Destination");
        Promotion memory _promotion = promotions[_promotionId];
        Claim memory _claim = claims[_promotionId][claimer];
        bytes32 hash = keccak256(
            abi.encodePacked(
                _promotionId,
                destinationDomain,
                _promotion.promotionAddress,
                msg.sender
            )
        );
        require(hash.recover(signature) == claimer, "unauthorized");
        require(_promotion.isExists, "Invalid Promotion");
        require(
            !_claim.isExists || _promotion.claimsPerPerson > _claim.claimsCount,
            "No more claims"
        );

        bytes memory message = abi.encode(claimer);
        bytes32 messageId = mailbox.dispatch(
            destinationDomain,
            addressToBytes32(_promotion.promotionAddress),
            message
        );

        uint256 quotedPayment = getQuotedPayment(destinationDomain, gasAmount);
        require(gasTank[_promotionId] >= quotedPayment, "Insufficient gas");
        gasTank[_promotionId] -= quotedPayment;
        igp.payForGas{value: quotedPayment}(
            messageId,
            destinationDomain,
            gasAmount,
            _promotion.creator
        );
        uint _currentClaims = _claim.claimsCount;
        claims[_promotionId][claimer] = Claim(
            destinationDomain,
            _promotion.promotionAddress,
            _currentClaims + 1,
            true
        );

        emit ClaimedPromotion(
            _promotionId,
            _promotion.promotionAddress,
            msg.sender,
            destinationDomain,
            _currentClaims + 1,
            block.timestamp
        );
    }

    function fillGas(bytes32 _promotionId) public payable {
        gasTank[_promotionId] += msg.value;
        emit GasTankFilled(_promotionId, gasTank[_promotionId]);
    }

    function refundGas(bytes32 _promotionId, address _to) public nonReentrant {
        require(msg.sender == promotions[_promotionId].creator, "Unauthorized");
        require(gasTank[_promotionId] > 0, "No balance");
        (bool success, bytes memory data) = payable(_to).call{
            value: gasTank[_promotionId]
        }("");
        if (success) {
            uint _gasAmount = gasTank[_promotionId];
            gasTank[_promotionId] = 0;
            emit GasTankRefunded(_promotionId, _gasAmount);
        } else {
            revert("Failed");
        }
    }

    // GETTERS
    function getQuotedPayment(uint32 destinationDomain, uint gasAmount)
        public
        view
        returns (uint256)
    {
        uint256 quotedPayment = igp.quoteGasPayment(
            destinationDomain,
            gasAmount
        );
        return quotedPayment;
    }

    // LIBRARY FUNCTIONS

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
