// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../contracts/domain/LoanContractRoles.sol";

import {AnzaDebtStorefront} from "../contracts/AnzaDebtStorefront.sol";
import {IDebtNotary} from "../contracts/interfaces/ILoanNotary.sol";
import {console, LoanContractSubmitted} from "./LoanContract.t.sol";
import {IAnzaDebtStorefrontEvents} from "./interfaces/IAnzaDebtStorefrontEvents.t.sol";
import {LibLoanNotary as Signing} from "../contracts/libraries/LibLoanNotary.sol";
import {LibLoanContractStates as States} from "../contracts/libraries/LibLoanContractConstants.sol";

contract AnzaDebtStorefrontUnitTest is
    IAnzaDebtStorefrontEvents,
    LoanContractSubmitted
{
    AnzaDebtStorefront public anzaDebtStorefront;

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
    }

    function createListingSignature(
        uint256 _price,
        uint256 _debtId
    ) public virtual returns (bytes memory _signature) {
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);
        uint256 _debtListingNonce = loanTreasurer.getDebtSaleNonce(_debtId);

        bytes32 _message = Signing.typeDataHash(
            IDebtNotary.DebtListingParams({
                price: _price,
                debtId: _debtId,
                debtListingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            }),
            Signing.DomainSeparator({
                name: "AnzaDebtStorefront",
                version: "0",
                chainId: block.chainid,
                contractAddress: address(anzaDebtStorefront)
            })
        );

        // Sign borrower's listing terms
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(borrowerPrivKey, _message);
        _signature = abi.encodePacked(r, s, v);
    }

    function testAnzaDebtStorefront__StorefrontStateVars() public {
        assertEq(anzaDebtStorefront.loanContract(), address(loanContract));
        assertEq(anzaDebtStorefront.loanTreasurer(), address(loanTreasurer));
        assertEq(anzaDebtStorefront.anzaToken(), address(anzaToken));
    }

    function testAnzaDebtStorefront__BasicBuyDebt() public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtId = loanContract.totalDebts();
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        bytes memory _signature = createListingSignature(_price, _debtId);

        uint256 _borrowerTokenId = anzaToken.borrowerTokenId(_debtId);
        assertTrue(
            anzaToken.checkBorrowerOf(borrower, _debtId),
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

        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            borrower,
            "3 :: AnzaToken owner should be borrower"
        );
        assertTrue(
            !anzaToken.checkBorrowerOf(borrower, _debtId),
            "4 :: borrower should not have AnzaToken borrower token role"
        );
        assertTrue(
            anzaToken.checkBorrowerOf(alt_account, _debtId),
            "5 :: alt_account should have AnzaToken borrower token role"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_ - _price,
            "6 :: Debt balance should be _PRINCIPAL_ - _price"
        );
    }

    function testAnzaDebtStorefront__ReplicaBuyDebt() public {
        uint256 _price = _PRINCIPAL_ - 1;
        uint256 _debtId = loanContract.totalDebts();
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        // Mint replica token
        vm.deal(borrower, 1 ether);
        vm.startPrank(borrower);
        loanContract.mintReplica(_debtId);
        vm.stopPrank();

        bytes memory _signature = createListingSignature(_price, _debtId);

        uint256 _borrowerTokenId = anzaToken.borrowerTokenId(_debtId);
        assertTrue(
            anzaToken.checkBorrowerOf(borrower, _debtId),
            "0 :: borrower should have AnzaToken borrower token role"
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
        vm.expectEmit(true, true, true, true);
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

        assertEq(
            anzaToken.ownerOf(_borrowerTokenId),
            alt_account,
            "3 :: AnzaToken owner should be alt_account"
        );
        assertTrue(
            !anzaToken.checkBorrowerOf(borrower, _debtId),
            "4 :: borrower should not have AnzaToken borrower token role"
        );
        assertTrue(
            anzaToken.checkBorrowerOf(alt_account, _debtId),
            "5 :: alt_account should have AnzaToken borrower token role"
        );
        assertEq(
            loanContract.debtBalanceOf(_debtId),
            _PRINCIPAL_ - _price,
            "6 :: Debt balance should be _PRINCIPAL_ - _price"
        );
    }
}
