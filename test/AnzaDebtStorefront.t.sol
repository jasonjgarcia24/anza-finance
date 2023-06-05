// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../contracts/domain/LoanContractRoles.sol";
import "../contracts/domain/LoanTreasureyErrorCodes.sol";

import {AnzaDebtStorefront} from "../contracts/AnzaDebtStorefront.sol";
import {IListingNotary} from "../contracts/interfaces/ILoanNotary.sol";
import {console, LoanContractSubmitted} from "./LoanContract.t.sol";
import {IAnzaDebtStorefrontEvents} from "./interfaces/IAnzaDebtStorefrontEvents.t.sol";
import {LibLoanNotary as Signing} from "../contracts/libraries/LibLoanNotary.sol";
import {LibLoanContractStates as States} from "../contracts/libraries/LibLoanContractConstants.sol";

abstract contract AnzaDebtStorefrontUnitTest is
    IAnzaDebtStorefrontEvents,
    LoanContractSubmitted
{
    AnzaDebtStorefront public anzaDebtStorefront;
    Signing.DomainSeparator public domainSeparator;

    function setUp() public virtual override {
        super.setUp();
        anzaDebtStorefront = new AnzaDebtStorefront(
            address(loanContract),
            address(loanTreasurer),
            address(anzaToken)
        );

        vm.startPrank(admin);
        loanTreasurer.grantRole(_DEBT_STOREFRONT_, address(anzaDebtStorefront));
        vm.stopPrank();

        domainSeparator = Signing.DomainSeparator({
            name: "AnzaDebtStorefront",
            version: "0",
            chainId: block.chainid,
            contractAddress: address(anzaDebtStorefront)
        });
    }

    function createListingSignature(
        uint256 _sellerPrivateKey,
        IListingNotary.ListingParams memory _debtListingParams
    ) public virtual returns (bytes memory _signature) {
        bytes32 _message = Signing.typeDataHash(
            _debtListingParams,
            domainSeparator
        );

        // Sign seller's listing terms
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_sellerPrivateKey, _message);
        _signature = abi.encodePacked(r, s, v);
    }
}

contract AnzaDebtStorefrontTest is AnzaDebtStorefrontUnitTest {
    function testAnzaDebtStorefront__StorefrontStateVars() public {
        assertEq(anzaDebtStorefront.loanContract(), address(loanContract));
        assertEq(anzaDebtStorefront.loanTreasurer(), address(loanTreasurer));
        assertEq(anzaDebtStorefront.anzaToken(), address(anzaToken));
    }
}

contract AnzaDebtStorefront__BasicBuyDebtTest is AnzaDebtStorefrontUnitTest {
    function testAnzaDebtStorefront__BasicBuyDebt() public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtId = loanContract.totalDebts();
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(_debtId);
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        uint256 _borrowerTokenId = anzaToken.borrowerTokenId(_debtId);
        assertEq(
            anzaToken.borrowerOf(_debtId),
            borrower,
            "0 :: borrower should be borrower"
        );
        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            borrower,
            "1 :: AnzaToken owner should be borrower"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_,
            "2 :: Debt balance should be _PRINCIPAL_"
        );

        vm.deal(alt_account, 4 ether);
        vm.startPrank(alt_account);
        vm.expectEmit(true, true, true, true, address(anzaDebtStorefront));
        emit DebtPurchased(alt_account, _debtId, _price);
        (bool _success, ) = address(anzaDebtStorefront).call{value: _price}(
            abi.encodeWithSignature(
                "buyDebt(uint256,uint256,bytes)",
                _debtId,
                _termsExpiry,
                _signature
            )
        );
        require(_success);
        vm.stopPrank();

        assertTrue(
            anzaToken.borrowerOf(_debtId) != borrower,
            "3 :: borrower account should not be borrower"
        );
        assertEq(
            anzaToken.borrowerOf(_debtId),
            alt_account,
            "4 :: alt_account account should be alt_account"
        );
        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            alt_account,
            "4 :: AnzaToken owner should be alt_account"
        );
        assertEq(
            anzaToken.lenderOf(_debtId),
            lender,
            "5 :: lender account should still be lender"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_ - _price,
            "6 :: Debt balance should be _PRINCIPAL_ - _price"
        );
    }

    function testAnzaDebtStorefront__BasicBuySponsorship() public {
        uint256 _debtId = loanContract.totalDebts();
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(_debtId);
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);
        uint256 _balance = loanContract.debtBalanceOf(_debtId);
        uint256 _price = _balance - 1;

        bytes memory _signature = createListingSignature(
            lenderPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        uint256 _lenderTokenId = anzaToken.lenderTokenId(_debtId);
        assertEq(
            anzaToken.lenderOf(_debtId),
            lender,
            "0 :: lender should be lender"
        );
        assertEq(
            anzaToken.ownerOf(_lenderTokenId),
            lender,
            "1 :: AnzaToken owner should be lender"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _balance,
            "2 :: Debt balance should be _balance"
        );

        vm.deal(alt_account, 4 ether);
        vm.startPrank(alt_account);
        vm.expectEmit(true, true, true, true, address(anzaDebtStorefront));
        emit DebtPurchased(alt_account, _debtId, _price);
        (bool _success, ) = address(anzaDebtStorefront).call{value: _price}(
            abi.encodeWithSignature(
                "buySponsorship(uint256,uint256,bytes)",
                _debtId,
                _termsExpiry,
                _signature
            )
        );
        require(_success);
        vm.stopPrank();

        uint256 _newDebtId = loanContract.totalDebts();
        uint256 _newLenderTokenId = anzaToken.lenderTokenId(_newDebtId);

        assertEq(
            anzaToken.lenderOf(_debtId),
            lender,
            "3 :: lender account should be lender for original debt ID"
        );
        assertEq(
            anzaToken.lenderOf(_newDebtId),
            alt_account,
            "4 :: alt_account account should be alt_account for new debt ID"
        );
        assertEq(
            anzaToken.ownerOf(_lenderTokenId),
            lender,
            "5 :: AnzaToken owner should be lender for original lender token ID"
        );
        assertEq(
            anzaToken.ownerOf(_newLenderTokenId),
            alt_account,
            "6 :: AnzaToken owner should be alt_account for new lender token ID"
        );
        assertEq(
            anzaToken.borrowerOf(_debtId),
            borrower,
            "7 :: borrower account should be borrower for original debt ID"
        );
        assertEq(
            anzaToken.borrowerOf(_newDebtId),
            borrower,
            "8 :: borrower account should be borrower for new debt ID"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            1,
            "9 :: Debt balance should be 1 for original debt ID"
        );
        assertEq(
            loanContract.debtBalanceOf(_newDebtId),
            _price >= _balance ? _balance : _price,
            "10 :: Debt balance should be min(_price, _balance) for new debt ID"
        );
    }
}

contract AnzaDebtStorefront__FuzzFailBuyDebt is AnzaDebtStorefrontUnitTest {
    function testAnzaDebtStorefront__FuzzFailPriceBuyDebt(
        uint256 _price
    ) public {
        uint256 _debtId = loanContract.totalDebts();
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(
            loanContract.totalDebts()
        );
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        vm.assume(_price != _PRINCIPAL_ - 1);

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        _testAnzaDebtStorefront__FuzzFailBuyDebt(
            IListingNotary.ListingParams({
                price: _PRINCIPAL_ - 1,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            }),
            _signature,
            _INVALID_PARTICIPANT_SELECTOR_
        );
    }

    function testAnzaDebtStorefront__FuzzFailDebtIdBuyDebt(
        uint256 _debtId
    ) public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(
            loanContract.totalDebts()
        );
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        vm.assume(_debtId != loanContract.totalDebts());

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        _testAnzaDebtStorefront__FuzzFailBuyDebt(
            IListingNotary.ListingParams({
                price: _price,
                debtId: loanContract.totalDebts(),
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            }),
            _signature,
            _INVALID_PARTICIPANT_SELECTOR_
        );
    }

    function testAnzaDebtStorefront__FuzzFailNonceBuyDebt(
        uint256 _debtListingNonce
    ) public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtId = loanContract.totalDebts();
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        vm.assume(
            _debtListingNonce !=
                loanTreasurer.getDebtSaleNonce(loanContract.totalDebts())
        );

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        _testAnzaDebtStorefront__FuzzFailBuyDebt(
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: loanTreasurer.getDebtSaleNonce(
                    loanContract.totalDebts()
                ),
                termsExpiry: _termsExpiry
            }),
            _signature,
            _INVALID_PARTICIPANT_SELECTOR_
        );
    }

    function testAnzaDebtStorefront__FuzzFailTermsExpiryBuyDebt(
        uint256 _termsExpiry
    ) public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtId = loanContract.totalDebts();
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(
            loanContract.totalDebts()
        );

        vm.assume(_termsExpiry > uint256(_TERMS_EXPIRY_));

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        _testAnzaDebtStorefront__FuzzFailBuyDebt(
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: uint256(_TERMS_EXPIRY_)
            }),
            _signature,
            _INVALID_PARTICIPANT_SELECTOR_
        );
    }

    function testAnzaDebtStorefront__FuzzFailAllBuyDebt(
        uint256 _price,
        uint256 _debtId,
        uint256 _debtListingNonce,
        uint256 _termsExpiry
    ) public {
        vm.assume(_price != _PRINCIPAL_ - 1);
        vm.assume(_debtId != loanContract.totalDebts());
        vm.assume(
            _debtListingNonce !=
                loanTreasurer.getDebtSaleNonce(loanContract.totalDebts())
        );
        vm.assume(_termsExpiry > uint256(_TERMS_EXPIRY_));

        bytes memory _signature = createListingSignature(
            borrowerPrivKey,
            IListingNotary.ListingParams({
                price: _price,
                debtId: _debtId,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        _testAnzaDebtStorefront__FuzzFailBuyDebt(
            IListingNotary.ListingParams({
                price: _PRINCIPAL_ - 1,
                debtId: loanContract.totalDebts(),
                listingNonce: loanTreasurer.getDebtSaleNonce(
                    loanContract.totalDebts()
                ),
                termsExpiry: uint256(_TERMS_EXPIRY_)
            }),
            _signature,
            _INVALID_PARTICIPANT_SELECTOR_
        );
    }

    function _testAnzaDebtStorefront__FuzzFailBuyDebt(
        IListingNotary.ListingParams memory _debtListingParams,
        bytes memory _signature,
        bytes4 _expectedError
    ) internal {
        uint256 _debtId = loanContract.totalDebts();

        uint256 _borrowerTokenId = anzaToken.borrowerTokenId(_debtId);
        assertEq(
            anzaToken.borrowerOf(_debtId),
            borrower,
            "0 :: borrower should be borrower"
        );
        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            borrower,
            "1 :: AnzaToken owner should be borrower"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_,
            "2 :: Debt balance should be _PRINCIPAL_"
        );

        vm.deal(alt_account, 4 ether);
        vm.startPrank(alt_account);

        (bool _success, bytes memory _data) = address(anzaDebtStorefront).call{
            value: _debtListingParams.price
        }(
            abi.encodeWithSignature(
                "buyDebt(uint256,uint256,bytes)",
                _debtListingParams.debtId,
                _debtListingParams.termsExpiry,
                _signature
            )
        );
        vm.stopPrank();

        assertTrue(_success == false, "3 :: buyDebt test should fail.");

        assertEq(
            bytes4(_data),
            _expectedError,
            "4 :: buyDebt test error type incorrect"
        );

        _borrowerTokenId = anzaToken.borrowerTokenId(_debtId);
        assertEq(
            anzaToken.borrowerOf(_debtId),
            borrower,
            "5 :: borrower should be unchanged"
        );
        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            borrower,
            "6 :: AnzaToken owner should be unchanged"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_,
            "7 :: Debt balance should be unchanged"
        );
    }
}
