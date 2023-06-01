// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILoanNotary {
    struct SignatureParams {
        uint256 principal;
        bytes32 contractTerms;
        address collateralAddress;
        uint256 collateralId;
        uint256 collateralNonce;
    }
}