// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10 <0.9.0;

import "@divergencetech/ethier/contracts/erc721/BaseTokenURI.sol";
import "@divergencetech/ethier/contracts/erc721/ERC721ACommon.sol";
import "@divergencetech/ethier/contracts/sales/FixedPriceSeller.sol";
import "@divergencetech/ethier/contracts/utils/Monotonic.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

interface ITokenURIGenerator {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// @author divergence.xyz
contract SSB is
    ERC721ACommon,
    BaseTokenURI,
    FixedPriceSeller,
    ERC2981,
    AccessControlEnumerable
{
    using Monotonic for Monotonic.Increaser;

    /**
    @notice Role of administrative users allowed to expel a NFT from the timer.
    @dev See expelFromTimer().
     */
    bytes32 public constant EXPULSION_ROLE = keccak256("EXPULSION_ROLE");

    constructor(
        string memory name,
        string memory symbol,
        address payable beneficiary,
        address payable royaltyReceiver
    )
        ERC721ACommon(name, symbol)
        BaseTokenURI("")
        FixedPriceSeller(
            2.5 ether,
            Seller.SellerConfig({
                totalInventory: 102,
                lockTotalInventory: true,
                maxPerAddress: 0,
                maxPerTx: 0,
                freeQuota: 102,
                lockFreeQuota: true,
                reserveFreeQuota: true
            }),
            beneficiary
        )
    {
        _setDefaultRoyalty(royaltyReceiver, 690);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
    @dev Mint tokens purchased via the Seller.
     */
    function _handlePurchase(
        address to,
        uint256 n,
        bool
    ) internal override {
        _safeMint(to, n);
        assert(totalSupply() <= 102);
    }

    /**
    @dev tokenId to timer start time (0 = not timer).
     */
    mapping(uint256 => uint256) private timerStarted;

    /**
    @dev Cumulative per-token timer, excluding the current period.
     */
    mapping(uint256 => uint256) private timerTotal;

    /**
    @notice Returns the length of time, in seconds, that the NFT has
    timed.
    @dev Timer is tied to a specific NFT, not to the owner, so it doesn't
    reset upon sale.
    @return timer Whether the NFT is currently timer. MAY be true with
    zero current timer if in the same block as timer began.
    @return current Zero if not currently timer, otherwise the length of time
    since the most recent timer began.
    @return total Total period of time for which the NFT has timed across
    its life, including the current period.
     */
    function timerPeriod(uint256 tokenId)
        external
        view
        returns (
            bool timer,
            uint256 current,
            uint256 total
        )
    {
        uint256 start = timerStarted[tokenId];
        if (start != 0) {
            timer = true;
            current = block.timestamp - start;
        }
        total = current + timerTotal[tokenId];
    }

    /**
    @dev MUST only be modified by safeTransferWhileTimer(); if set to 2 then
    the _beforeTokenTransfer() block while timer is disabled.
     */
    uint256 private timerTransfer = 1;

    /**
    @notice Transfer a token between addresses while the NFT is minting,
    thus not resetting the timer period.
     */
    function safeTransferWhileTimer(
        address from,
        address to,
        uint256 tokenId
    ) external {
        require(ownerOf(tokenId) == _msgSender(), "NFTs: Only owner");
        timerTransfer = 2;
        safeTransferFrom(from, to, tokenId);
        timerTransfer = 1;
    }

    /**
    @dev Block transfers while timer.
     */
    function _beforeTokenTransfers(
        address,
        address,
        uint256 startTokenId,
        uint256 quantity
    ) internal view override {
        uint256 tokenId = startTokenId;
        for (uint256 end = tokenId + quantity; tokenId < end; ++tokenId) {
            require(
                timerStarted[tokenId] == 0 || timerTransfer == 2,
                "NFTs: timer"
            );
        }
    }

    /**
    @dev Emitted when a NFT begins timer.
     */
    event Timed(uint256 indexed tokenId);

    /**
    @dev Emitted when a NFT stops timer; either through standard means or
    by expulsion.
     */
    event Untimed(uint256 indexed tokenId);

    /**
    @dev Emitted when a NFT is expelled from the timer.
     */
    event Expelled(uint256 indexed tokenId);

    /**
    @notice Whether timer is currently allowed.
    @dev If false then timer is blocked, but untimer is always allowed.
     */
    bool public timerOpen = false;

    /**
    @notice Toggles the `timerOpen` flag.
     */
    function setTimerOpen(bool open) external onlyOwner {
        timerOpen = open;
    }

    /**
    @notice Changes the NFT's timer status.
    */
    function toggleTimer(uint256 tokenId)
        internal
        onlyApprovedOrOwner(tokenId)
    {
        uint256 start = timerStarted[tokenId];
        if (start == 0) {
            require(timerOpen, "NFTs: timer closed");
            timerStarted[tokenId] = block.timestamp;
            emit Timed(tokenId);
        } else {
            timerTotal[tokenId] += block.timestamp - start;
            timerStarted[tokenId] = 0;
            emit Untimed(tokenId);
        }
    }

    /**
    @notice Changes the NFTs' timer statuss (what's the plural of status?
    statii? statuses? status? The plural of sheep is sheep; maybe it's also the
    plural of status).
    @dev Changes the NFTs' timer sheep (see @notice).
     */
    function toggleTimer(uint256[] calldata tokenIds) external {
        uint256 n = tokenIds.length;
        for (uint256 i = 0; i < n; ++i) {
            toggleTimer(tokenIds[i]);
        }
    }

    /**
    @notice Admin-only ability to expel a NFT from the timer.
    @dev As most sales listings use off-chain signatures it's impossible to
    detect someone who has timed and then deliberately undercuts the floor
    price in the knowledge that the sale can't proceed. This function allows for
    monitoring of such practices and expulsion if abuse is detected, allowing
    the undercutting bird to be sold on the open market. Since OpenSea uses
    isApprovedForAll() in its pre-listing checks, we can't block by that means
    because timer would then be all-or-nothing for all of a particular owner's
    NFTs.
     */
    function expelFromTimer(uint256 tokenId) external onlyRole(EXPULSION_ROLE) {
        require(timerStarted[tokenId] != 0, "NFTs: not timed");
        timerTotal[tokenId] += block.timestamp - timerStarted[tokenId];
        timerStarted[tokenId] = 0;
        emit Untimed(tokenId);
        emit Expelled(tokenId);
    }

    /**
    @dev Required override to select the correct baseTokenURI.
     */
    function _baseURI()
        internal
        view
        override(BaseTokenURI, ERC721A)
        returns (string memory)
    {
        return BaseTokenURI._baseURI();
    }

    /**
    @notice If set, contract to which tokenURI() calls are proxied.
     */
    ITokenURIGenerator public renderingContract;

    /**
    @notice Sets the optional tokenURI override contract.
     */
    function setRenderingContract(ITokenURIGenerator _contract)
        external
        onlyOwner
    {
        renderingContract = _contract;
    }

    /**
    @notice If renderingContract is set then returns its tokenURI(tokenId)
    return value, otherwise returns the standard baseTokenURI + tokenId.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (address(renderingContract) != address(0)) {
            return renderingContract.tokenURI(tokenId);
        }
        return super.tokenURI(tokenId);
    }

    /**
    @notice Sets the contract-wide royalty info.
     */
    function setRoyaltyInfo(address receiver, uint96 feeBasisPoints)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeBasisPoints);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721ACommon, ERC2981, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}