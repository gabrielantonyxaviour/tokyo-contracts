// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./lib/libs/zk-connect/ZkConnectLib.sol";
import "./interfaces/IInterchainQueryRouter.sol";
import "./interfaces/IMailbox.sol";
import "./interfaces/IInterchainGasPaymaster.sol";
import "./interfaces/IReceiver.sol";
import "./ZaisanSismoNFT.sol";
import "./ZaisanTokenNFT.sol";

interface IPromotion {
    function isERC1155(address nftAddress) external returns (bool);

    function isERC721(address nftAddress) external returns (bool);
}

contract PromotionMain is IPromotion, Ownable, ReentrancyGuard, ZkConnect {
    using ECDSA for bytes32;
    using ERC165Checker for address;

    enum PromotionState {
        DOES_NOT_EXIST,
        SISMO_PROMOTION,
        TOKEN_PROMOTION
    }

    enum ClaimState {
        DOES_NOT_EXIST,
        AVAILABLE,
        EXHAUSTED,
        WAITING
    }

    struct Receiver {
        bytes32 destinationReceiverAddress;
        address destinationMailbox;
        bool isExists;
    }

    struct Promotion {
        address promotionAddress;
        uint32 destinationDomain;
        address creator;
        uint createdAt;
        uint claimsPerPerson;
        bytes16 groupId;
        string functionSignature;
        uint gasEthLeft;
        PromotionState state;
    }

    struct PromotionClaim {
        uint32 destinationDomain;
        address promotionAddress;
        uint claimsCount;
        ClaimState state;
    }
    bytes4 public constant IID_PROMOTION = type(IPromotion).interfaceId;
    bytes4 public constant IID_IERC165 = type(IERC165).interfaceId;
    bytes4 public constant IID_IERC1155 = type(IERC1155).interfaceId;
    bytes4 public constant IID_IERC721 = type(IERC721).interfaceId;

    mapping(bytes32 => Promotion) public promotions; // Promotion Id => Promotion
    mapping(bytes32 => mapping(address => PromotionClaim)) public claims; // Promotion Id => Claimer => Claim

    mapping(uint32 => Receiver) public chains; // Destination Chain to Receiver Data

    IMailbox public constant mailbox =
        IMailbox(0xCC737a94FecaeC165AbCf12dED095BB13F037685);
    IInterchainGasPaymaster public constant igp =
        IInterchainGasPaymaster(0xF90cB82a76492614D07B82a7658917f3aC811Ac1);
    IInterchainQueryRouter public constant iqsRouter =
        IInterchainQueryRouter(0xF782C6C4A02f2c71BB8a1Db0166FAB40ea956818);

    constructor(bytes16 appId) ZkConnect(appId) {}

    event NewChainAdded(uint32 destinationDomain);
    event GasTankRefunded(bytes32 promotionId, address claimer, uint256 amount);
    event SismoPromotionCreated(
        bytes32 promotionId,
        bytes16 groupId,
        address creator,
        uint createdAt,
        uint claimsPerPerson,
        string badgeURI
    );
    event TokenPromotionCreated(
        bytes32 promotionId,
        uint32 destinationDomain,
        address creator,
        uint createdAt,
        uint claimsPerPerson,
        uint gasEthLeft,
        string badgeURI
    );

    event SismoPromotionClaimed(
        bytes32 promotionId,
        address claimer,
        uint claimsCount,
        uint claimedAt
    );
    event GasTankFilled(bytes32 _promotionId, uint gasEthLeft);

    // ERC 20 - Token Count balanceOf(address)=>(uint)
    // ERC721 - Token Count balanceOf(address)=>(uint), Specific Token Ownership ownerOf(uint)=>address
    // ERC1155 - Specific Token Count balanceOf(address,uint)=>(uint)

    function _claimPreCheck(
        Promotion memory _promotion,
        PromotionClaim memory _claim
    ) internal pure {
        require(
            _promotion.state != PromotionState.DOES_NOT_EXIST,
            "Invalid Promotion"
        );
        require(_claim.state != ClaimState.EXHAUSTED, "No more claims");
        require(
            _claim.state != ClaimState.WAITING,
            "Processing previous claim"
        );
    }

    function addChain(
        uint32 destinationDomain,
        address destinationReceiver,
        address destinationMailbox
    ) public onlyOwner {
        chains[destinationDomain] = Receiver(
            addressToBytes32(destinationReceiver),
            destinationMailbox,
            true
        );
    }

    function createTokenPromotion(
        uint32 destinationDomain,
        uint claimsPerPerson,
        string memory badgeURI,
        string calldata functionSignature,
        uint relayerGas,
        uint promotionAction,
        uint _salt
    ) public payable {
        require(chains[destinationDomain].isExists, "Invalid Destination");
        // 1. Create PromotionNFT contract in destination chain and Fill Gas
        bytes memory message = abi.encode(
            badgeURI,
            msg.sender,
            claimsPerPerson,
            bytes32(_salt),
            functionSignature
        );

        bytes32 messageId = mailbox.dispatch(
            destinationDomain,
            chains[destinationDomain].destinationReceiverAddress,
            message
        );
        address _promotionAddress = _getAddress(
            destinationDomain,
            badgeURI,
            msg.sender,
            _salt
        );

        bytes32 _promotionId = keccak256(
            abi.encodePacked(
                _promotionAddress,
                destinationDomain,
                functionSignature,
                badgeURI,
                block.timestamp
            )
        );
        require(
            promotions[_promotionId].state == PromotionState.DOES_NOT_EXIST,
            "Promotion exists"
        );

        // 2. Get gas amount
        uint256 quotedPayment = getQuotedPayment(destinationDomain);
        require(msg.value >= quotedPayment, "Insufficient gas");

        // 3. Pay for Interchain Gas
        igp.payForGas{value: quotedPayment}(
            messageId,
            destinationDomain,
            relayerGas,
            msg.sender
        );

        // 4. Update State Variables
        promotions[_promotionId] = Promotion(
            _promotionAddress,
            destinationDomain,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            0x0,
            functionSignature,
            msg.value - quotedPayment,
            PromotionState.TOKEN_PROMOTION
        );

        // 5. Emit events

        emit TokenPromotionCreated(
            _promotionId,
            destinationDomain,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            msg.value - quotedPayment,
            badgeURI
        );
    }

    function createSismoPromotion(
        uint claimsPerPerson,
        string memory badgeURI,
        bytes16 groupId,
        uint salt
    ) public {
        require(claimsPerPerson > 0, "zero claims");
        bytes32 _promotionId = keccak256(
            abi.encodePacked(groupId, badgeURI, block.timestamp)
        );
        require(
            promotions[_promotionId].state == PromotionState.DOES_NOT_EXIST,
            "Promotion exists"
        );
        ZaisanSismoNFT promotion = (new ZaisanSismoNFT){salt: bytes32(salt)}(
            badgeURI,
            msg.sender
        );

        // 4. Update State Variables
        promotions[_promotionId] = Promotion(
            address(promotion),
            0,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            groupId,
            "",
            0,
            PromotionState.SISMO_PROMOTION
        );

        // 5. Emit events

        emit SismoPromotionCreated(
            _promotionId,
            groupId,
            msg.sender,
            block.timestamp,
            claimsPerPerson,
            badgeURI
        );
    }

    function claimTokenPromotion(
        bytes32 _promotionId,
        uint32 destinationDomain,
        address claimer
    ) public {
        // Verifications
        require(chains[destinationDomain].isExists, "Invalid Destination");

        Promotion memory _promotion = promotions[_promotionId];
        PromotionClaim memory _claim = claims[_promotionId][claimer];
        _claimPreCheck(_promotion, _claim);

        // Make Query call
        iqsRouter.query(_promotion.destinationDomain,_promotion.promotionAddress,abi.encodeWithSignature(_promotion.functionSignature, []);)

        // Send message crossChain
        // bytes32 messageId = mailbox.dispatch(
        //     destinationDomain,
        //     addressToBytes32(_promotion.promotionAddress),
        //     abi.encode(claimer)
        // );

        // uint256 quotedPayment = getQuotedPayment(destinationDomain);
        // require(gasTank[_promotionId] >= quotedPayment, "Insufficient gas");
        // igp.payForGas{value: quotedPayment}(
        //     messageId,
        //     destinationDomain,
        //     50000,
        //     _promotion.creator
        // );
        // uint _currentClaims = _claim.claimsCount;
        // if (_currentClaims + 1 == _promotion.claimsPerPerson) {
        //     claims[_promotionId][claimer] = PromotionClaim(
        //         destinationDomain,
        //         _promotion.promotionAddress,
        //         _currentClaims + 1,
        //         ClaimState.WAITING
        //     );
        // }

        // emit ClaimedPromotion(
        //     _promotionId,
        //     msg.sender,
        //     _currentClaims + 1,
        //     block.timestamp
        // );
    }

    function claimSismoPromotion(
        bytes32 _promotionId,
        address claimer,
        bytes memory zkConnectResponse,
        bytes calldata encodedParams
    ) public {
        // Verifications
        Promotion memory _promotion = promotions[_promotionId];
        PromotionClaim memory _claim = claims[_promotionId][claimer];
        require(_promotion.state == PromotionState.SISMO_PROMOTION, "invalid");
        require(_claim.state != ClaimState.EXHAUSTED, "exhausted");
        _claimPreCheck(_promotion, _claim);
        verify({
            responseBytes: zkConnectResponse,
            authRequest: buildAuth({authType: AuthType.ANON}),
            claimRequest: buildClaim({groupId: _promotion.groupId}),
            messageSignatureRequest: encodedParams
        });
        ZaisanSismoNFT(_promotion.promotionAddress).claim(claimer);
        uint _currentClaims = _claim.claimsCount;
        if (_currentClaims + 1 == _promotion.claimsPerPerson) {
            claims[_promotionId][claimer] = PromotionClaim(
                0,
                _promotion.promotionAddress,
                _currentClaims + 1,
                ClaimState.EXHAUSTED
            );
        } else {
            claims[_promotionId][claimer] = PromotionClaim(
                0,
                _promotion.promotionAddress,
                _currentClaims + 1,
                ClaimState.AVAILABLE
            );
        }

        emit SismoPromotionClaimed(
            _promotionId,
            msg.sender,
            _currentClaims + 1,
            block.timestamp
        );
    }

    function fillGas(bytes32 _promotionId) public payable {
        promotions[_promotionId].gasEthLeft += msg.value;
        emit GasTankFilled(_promotionId, promotions[_promotionId].gasEthLeft);
    }

    function refundGas(bytes32 _promotionId, address _to) public nonReentrant {
        require(msg.sender == promotions[_promotionId].creator, "Unauthorized");
        require(promotions[_promotionId].gasEthLeft > 0, "No balance");
        (bool success, ) = payable(_to).call{
            value: promotions[_promotionId].gasEthLeft
        }("");
        if (success) {
            uint _gasAmount = promotions[_promotionId].gasEthLeft;
            promotions[_promotionId].gasEthLeft = 0;
            emit GasTankRefunded(_promotionId, _to, _gasAmount);
        } else {
            revert("Failed");
        }
    }

    // GETTERS
    function getQuotedPayment(uint32 destinationDomain)
        public
        view
        returns (uint256)
    {
        uint256 gasAmount = 50000;
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

    function isERC1155(address nftAddress) public view override returns (bool) {
        return nftAddress.supportsInterface(IID_IERC1155);
    }

    function isERC721(address nftAddress)
        external
        view
        override
        returns (bool)
    {
        return nftAddress.supportsInterface(IID_IERC721);
    }

    function _getAddress(
        uint32 destinationDomain,
        string memory badgeURI,
        address creator,
        uint _salt
    ) internal view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(ZaisanTokenNFT).creationCode,
            abi.encode(
                badgeURI,
                msg.sender,
                creator,
                chains[destinationDomain].destinationMailbox
            )
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

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == IID_PROMOTION || interfaceId == IID_IERC165;
    }
}
