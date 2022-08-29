// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ComedyNFT is
    ERC721Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;
    using AddressUpgradeable for address;

    struct NFTData {
        string metadata;
        address textUploader;
        address textVoter;
    }

    struct AuctionData {
        address owner;
        uint256 tokenId;
        address topBidder;
        uint256 bidAmount;
        uint256 auctinEndTime;
        bool available;
        bool started;
    }

    CountersUpgradeable.Counter private _tokenIds;
    address private signer;

    mapping(uint256 => NFTData) private nftDatas;
    mapping(uint256 => AuctionData) public auctionData;

    event NFTMinted(uint256 tokenId);
    event NewAuctionCreated(uint256 tokenId);
    event AuctionEnded(uint256 tokenId, address bidder, uint256 bidAmount);

    function initialize() public initializer {
        __ERC721_init("Comedy NFT", "Comedy");
        _setDefaultRoyalty(msg.sender, 100); // set default royalty address, 1%
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function burnNFT(uint256 tokenId)
        public onlyOwner {
        _burn(tokenId);
    }

    function mintNFT(
        uint256 quantity,
        string[] memory metadataURLs,
        address[] memory textUploaders,
        address[] memory textVoters,
        bytes calldata signature
    ) external {
        verifySigner(signature);
        require(
            (quantity == metadataURLs.length) &&
                (quantity == textUploaders.length) &&
                (quantity == textVoters.length),
            "Invalid metadata length"
        );

        uint256 newItemId = _tokenIds.current();

        for (uint256 i = 0; i < quantity; i += 1) {
            _tokenIds.increment();
            _mint(address(this), newItemId);
            nftDatas[newItemId] = NFTData(
                metadataURLs[i],
                textUploaders[i],
                textVoters[i]
            );
            AuctionData storage newAuction = auctionData[newItemId];
            newAuction.available = true;
            newAuction.owner = address(this);
            newAuction.tokenId = newItemId;
            emit NFTMinted(newItemId);
        }
    }

    function verifySigner(bytes calldata signature) public view {
        bytes32 hash = keccak256(abi.encodePacked(msg.sender));
        bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(hash);
        address receivedAddress = ECDSAUpgradeable.recover(message, signature);
        require(receivedAddress != address(0) && receivedAddress == signer);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return nftDatas[tokenId].metadata;
    }

    function tokenData(uint256 tokenId) public view returns (NFTData memory) {
        return nftDatas[tokenId];
    }

    function startAuction(uint256 tokenId, uint256 auctionEndTime)
        external
        onlyOwner
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        require(ownerOf(tokenId) == address(this), "Not available nft");
        AuctionData storage newAuction = auctionData[tokenId];
        newAuction.auctinEndTime = auctionEndTime;
        newAuction.available = false;
        newAuction.started = true;

        emit NewAuctionCreated(tokenId);
    }

    function bid(uint256 tokenId) external payable nonReentrant {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        AuctionData storage newAuction = auctionData[tokenId];
        require(newAuction.started, "This auction is not started");
        require(
            block.timestamp <= newAuction.auctinEndTime,
            "Auction already ended"
        );
        require(
            msg.value > newAuction.bidAmount,
            "Bid amount should be bigger than current amount"
        );

        // Refund to previous bidder
        payable(newAuction.topBidder).transfer(newAuction.bidAmount);

        newAuction.bidAmount = msg.value;
        newAuction.topBidder = msg.sender;
    }

    function endAuction(uint256 tokenId) external {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        AuctionData storage auction = auctionData[tokenId];
        require(auction.started, "This auction is not started");
        require(
            block.timestamp > auction.auctinEndTime,
            "Auction is in progress"
        );

        auction.available = false;
        auction.started = false;
        transferFrom(auction.owner, auction.topBidder, tokenId);

        uint256 amountFortextBidder = (auction.bidAmount * 7) / 10;

        payable(nftDatas[tokenId].textUploader).transfer(amountFortextBidder); // 70% to text uploader
        payable(nftDatas[tokenId].textVoter).transfer(
            auction.bidAmount - amountFortextBidder
        ); // 30% to text voter (selected randomly)

        emit AuctionEnded(tokenId, auction.topBidder, auction.bidAmount);
    }

    function getAuctionData(uint256 tokenId)
        public
        view
        returns (AuctionData memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return auctionData[tokenId];
    }

    // Set royalty for entire collection 100: 1%, 1000: 10%, 10000: 100%
    function setRoyaltyInfo(address _receiver, uint96 _royaltyPercent) external onlyOwner {
        _setDefaultRoyalty(_receiver, _royaltyPercent);
    }

    // Set royalty for individual nft instance
    function setTokenRoyalty(uint _tokenId, address _receiver, uint96 _feeAmount) external onlyOwner {
        _setTokenRoyalty(_tokenId, _receiver, _feeAmount);
    }
}
