// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILoanNotaryErrors {
    error InvalidParticipant();
    error InvalidSignatureLength();
}

interface ILoanNotary is ILoanNotaryErrors {
    struct ContractParams {
        uint256 principal;
        bytes32 contractTerms;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralNonce;
    }
}

interface IDebtNotary is ILoanNotaryErrors {
    struct DebtListingParams {
        uint256 price;
        uint256 debtId;
        uint256 debtListingNonce;
        uint256 termsExpiry;
    }
}
