// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../lib/forge-std/src/console.sol";

import {ListingNotary} from "./LoanNotary.sol";
import "./interfaces/IAnzaToken.sol";
import "./interfaces/IAnzaDebtStorefront.sol";
import "./interfaces/ILoanContract.sol";
import "./interfaces/ILoanTreasurey.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AnzaDebtStorefront is
    IAnzaDebtStorefront,
    ListingNotary,
    ReentrancyGuard
{
    /* ------------------------------------------------ *
     *              Priviledged Accounts                *
     * ------------------------------------------------ */
    address public immutable loanContract;
    address public immutable loanTreasurer;
    address public immutable anzaToken;

    mapping(address beneficiary => uint256) private __proceeds;

    constructor(
        address _loanContract,
        address _loanTreasurer,
        address _anzaToken
    ) ListingNotary("AnzaDebtStorefront", "0") {
        loanContract = _loanContract;
        loanTreasurer = _loanTreasurer;
        anzaToken = _anzaToken;
    }

    function buyDebt(
        address _collateralAddress,
        uint256 _collateralId,
        uint256 _termsExpiry,
        bytes calldata _sellerSignature
    ) external payable {
        (bool success, ) = address(this).call{value: msg.value}(
            abi.encodeWithSignature(
                "buyDebt(uint256,uint256,bytes)",
                ILoanContract(loanContract).getCollateralDebtId(
                    _collateralAddress,
                    _collateralId
                ),
                _termsExpiry,
                _sellerSignature
            )
        );
        require(success);
    }

    function buyDebt(
        uint256 _debtId,
        uint256 _termsExpiry,
        bytes calldata _sellerSignature
    ) public payable {
        _buyListing(
            IAnzaToken(anzaToken).borrowerTokenId(_debtId),
            _termsExpiry,
            msg.value,
            _sellerSignature,
            "executeDebtPurchase(uint256,address,address)"
        );
    }

    function buySponsorship(
        address _collateralAddress,
        uint256 _collateralId,
        uint256 _termsExpiry,
        bytes calldata _sellerSignature
    ) external payable {
        (bool success, ) = address(this).call{value: msg.value}(
            abi.encodeWithSignature(
                "buySponsorship(uint256,uint256,bytes)",
                ILoanContract(loanContract).getCollateralDebtId(
                    _collateralAddress,
                    _collateralId
                ),
                _termsExpiry,
                _sellerSignature
            )
        );
        require(success);
    }

    function buySponsorship(
        uint256 _debtId,
        uint256 _termsExpiry,
        bytes calldata _sellerSignature
    ) public payable {
        _buyListing(
            IAnzaToken(anzaToken).lenderTokenId(_debtId),
            _termsExpiry,
            msg.value,
            _sellerSignature,
            "executeSponsorshipPurchase(uint256,address,address)"
        );
    }

    function refinance() public payable nonReentrant {}

    function _buyListing(
        uint256 _tokenId,
        uint256 _termsExpiry,
        uint256 _price,
        bytes calldata _sellerSignature,
        string memory _purchaseListingMethod
    ) internal virtual nonReentrant {
        uint256 _debtId = IAnzaToken(anzaToken).debtId(_tokenId);

        // Verify seller participation
        address _seller = _getSigner(
            _tokenId,
            ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: ILoanTreasurey(loanTreasurer).getDebtSaleNonce(
                    _debtId
                ),
                termsExpiry: _termsExpiry
            }),
            _sellerSignature,
            IAnzaToken(anzaToken).ownerOf
        );

        // Transfer debt
        (bool _success, ) = loanTreasurer.call{value: _price}(
            abi.encodeWithSignature(
                _purchaseListingMethod,
                _debtId,
                _seller,
                msg.sender
            )
        );
        require(_success);

        emit DebtPurchased(msg.sender, _debtId, _price);
    }
}
