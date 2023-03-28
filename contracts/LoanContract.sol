// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "hardhat/console.sol";
import "./token/interfaces/IAnzaToken.sol";
import "./interfaces/ILoanContract.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import {LibOfficerRoles as Roles} from "./libraries/LibLoanContract.sol";

contract LoanContract is ILoanContract, AccessControl, ERC1155Holder {
    /* ------------------------------------------------ *
     *                Contract Constants                *
     * ------------------------------------------------ */
    uint256 private constant _SECONDS_PER_24_MINUTES_RATIO_SCALED_ = 1440;
    uint256 private constant _UINT32_MAX_ = 4294967295;

    /* ------------------------------------------------ *
     *                  Loan States                     *
     * ------------------------------------------------ */
    uint8 private constant _UNDEFINED_STATE_ = 0;
    uint8 private constant _NONLEVERAGED_STATE_ = 1;
    uint8 private constant _UNSPONSORED_STATE_ = 2;
    uint8 private constant _SPONSORED_STATE_ = 3;
    uint8 private constant _FUNDED_STATE_ = 4;
    uint8 private constant _ACTIVE_GRACE_STATE_ = 5;
    uint8 private constant _ACTIVE_STATE_ = 6;
    uint8 private constant _DEFAULT_STATE_ = 7;
    uint8 private constant _COLLECTION_STATE_ = 8;
    uint8 private constant _AUCTION_STATE_ = 9;
    uint8 private constant _AWARDED_STATE_ = 10;
    uint8 private constant _CLOSE_STATE_ = 11;
    uint8 private constant _PAID_STATE_ = 12;

    /* ------------------------------------------------ *
     *       Fixed Interest Rate (FIR) Intervals        *
     * ------------------------------------------------ */
    //  Need to validate duration > FIR interval
    uint8 private constant _SECONDLY_ = 0;
    uint8 private constant _MINUTELY_ = 1;
    uint8 private constant _HOURLY_ = 2;
    uint8 private constant _DAILY_ = 3;
    uint8 private constant _WEEKLY_ = 4;
    uint8 private constant _2_WEEKLY_ = 5;
    uint8 private constant _4_WEEKLY_ = 6;
    uint8 private constant _6_WEEKLY_ = 7;
    uint8 private constant _8_WEEKLY_ = 8;
    uint8 private constant _MONTHLY_ = 9;
    uint8 private constant _2_MONTHLY_ = 10;
    uint8 private constant _3_MONTHLY_ = 11;
    uint8 private constant _4_MONTHLY_ = 12;
    uint8 private constant _6_MONTHLY_ = 13;
    uint8 private constant _360_DAILY_ = 14;
    uint8 private constant _ANNUALLY_ = 15;

    /* ------------------------------------------------ *
     *               FIR Interval Multipliers           *
     * ------------------------------------------------ */
    uint256 private constant _SECONDLY_MULTIPLIER_ = 1;
    uint256 private constant _MINUTELY_MULTIPLIER_ = 60;
    uint256 private constant _HOURLY_MULTIPLIER_ = 60 * 60;
    uint256 private constant _DAILY_MULTIPLIER_ = 60 * 60 * 24;
    uint256 private constant _WEEKLY_MULTIPLIER_ = 60 * 60 * 24 * 7;
    uint256 private constant _2_WEEKLY_MULTIPLIER_ = 60 * 60 * 24 * 7 * 2;
    uint256 private constant _4_WEEKLY_MULTIPLIER_ = 60 * 60 * 24 * 7 * 4;
    uint256 private constant _6_WEEKLY_MULTIPLIER_ = 60 * 60 * 24 * 7 * 6;
    uint256 private constant _8_WEEKLY_MULTIPLIER_ = 60 * 60 * 24 * 7 * 8;
    uint256 private constant _360_DAILY_MULTIPLIER_ = 60 * 60 * 24 * 360;
    uint256 private constant _365_DAILY_MULTIPLIER_ = 60 * 60 * 24 * 365;

    /* ------------------------------------------------ *
     *           Packed Debt Term Mappings              *
     * ------------------------------------------------ */
    uint256 private constant _LOAN_STATE_MASK_ =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0;
    uint256 private constant _LOAN_STATE_MAP_ =
        0x000000000000000000000000000000000000000000000000000000000000000F;
    uint256 private constant _FIR_INTERVAL_MASK_ =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0F;
    uint256 private constant _FIR_INTERVAL_MAP_ =
        0x00000000000000000000000000000000000000000000000000000000000000F0;
    uint256 private constant _FIR_MASK_ =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FF;
    uint256 private constant _FIR_MAP_ =
        0x000000000000000000000000000000000000000000000000000000000000FF00;
    uint256 private constant _LOAN_START_MASK_ =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFF;
    uint256 private constant _LOAN_START_MAP_ =
        0x0000000000000000000000000000000000000000000000000000FFFFFFFF0000;
    uint256 private constant _LOAN_DURATION_MASK_ =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFF;
    uint256 private constant _LOAN_DURATION_MAP_ =
        0x00000000000000000000000000000000000000000000FFFFFFFF000000000000;
    uint256 private constant _BORROWER_MASK_ =
        0xFFFF0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFF;
    uint256 private constant _BORROWER_MAP_ =
        0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000;
    uint256 private constant _LENDER_ROYALTIES_MASK_ =
        0xFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant _LENDER_ROYALTIES_MAP_ =
        0x00FF000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant _CLEANUP_MASK_ = (1 << 252) - 1;

    /* ------------------------------------------------ *
     *           Loan Term Standard Errors              *
     * ------------------------------------------------ */
    bytes4 private constant _LOAN_STATE_ERROR_ID_ = 0xdacce9d3;
    bytes4 private constant _FIR_INTERVAL_ERROR_ID_ = 0xa13e8948;
    bytes4 private constant _DURATION_ERROR_ID_ = 0xfcbf8511;
    bytes4 private constant _PRINCIPAL_ERROR_ID_ = 0x6a901435;
    bytes4 private constant _FIXED_INTEREST_RATE_ERROR_ID_ = 0x8fe03ac3;
    bytes4 private constant _GRACE_PERIOD_ERROR_ID_ = 0xb677e65e;
    bytes4 private constant _TIME_EXPIRY_ERROR_ID_ = 0x67b21a5c;

    /* ------------------------------------------------ *
     *              Priviledged Accounts                *
     * ------------------------------------------------ */
    address public immutable collateralVault;
    IAnzaToken public anzaToken;

    /* ------------------------------------------------ *
     *                    Databases                     *
     * ------------------------------------------------ */
    // Mapping from collateral to debt ID
    mapping(address => mapping(uint256 => uint256[])) public debtIds;

    //  > 004 - [0..3]     `loanState`
    //  > 004 - [4..7]     `firInterval`
    //  > 008 - [8..15]    `fixedInterestRate`
    //  > 032 - [16..47]   `loanStart`
    //  > 032 - [48..79]   `loanDuration`
    //  > 160 - [80..239]  `borrower`
    //  > 008 - [240..247] `lenderRoyalties`
    //  > 008 - [248..255] extra space
    mapping(uint256 => bytes32) private __packedDebtTerms;

    // Mapping from participant to withdrawable balance
    mapping(address => uint256) public withdrawableBalance;

    // Count of total inactive/active debts
    uint256 public totalDebts;

    constructor(address _collateralVault) {
        _setRoleAdmin(Roles._ADMIN_, Roles._ADMIN_);
        _setRoleAdmin(Roles._TREASURER_, Roles._ADMIN_);
        _setRoleAdmin(Roles._COLLECTOR_, Roles._ADMIN_);

        _grantRole(Roles._ADMIN_, msg.sender);

        collateralVault = _collateralVault;
    }

    function setAnzaToken(
        address _anzaTokenAddress
    ) external onlyRole(Roles._ADMIN_) {
        anzaToken = IAnzaToken(_anzaTokenAddress);
    }

    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(AccessControl, ERC1155Receiver) returns (bool) {
        return
            _interfaceId == type(ILoanContract).interfaceId ||
            ERC1155Receiver.supportsInterface(_interfaceId) ||
            AccessControl.supportsInterface(_interfaceId);
    }

    /*
     * This should report back only the total debt tokens, not the ALC NFTs.
     * TODO: Test
     */
    function debtBalanceOf(uint256 _debtId) public view returns (uint256) {
        return anzaToken.totalSupply(_debtId * 2);
    }

    function getCollateralNonce(
        address _collateralAddress,
        uint256 _collateralId
    ) public view returns (uint256) {
        return debtIds[_collateralAddress][_collateralId].length;
    }

    function getCollateralDebtId(
        address _collateralAddress,
        uint256 _collateralId
    ) public view returns (uint256) {
        return
            debtIds[_collateralAddress][_collateralId][
                debtIds[_collateralAddress][_collateralId].length - 1
            ];
    }

    function getDebtTerms(uint256 _debtId) external view returns (bytes32) {
        return __packedDebtTerms[_debtId];
    }

    /*
     * TODO: Test
     *
     * Input _contractTerms:
     *  > 008 - [0..7]     `loanState`
     *  > 008 - [8..15]    `fixedInterestRate`
     *  > 128 - [16..143]  `principal`
     *  > 032 - [144..175] `gracePeriod`
     *  > 032 - [176..207] `duration`
     *  > 032 - [208..239] `termsExpiry`
     *  > 016 - [240..255] unused space
     *
     * Saved _contractAgreement:
     *  > 008 - [0..7]     `loanState`
     *  > 008 - [8..15]    `fixedInterestRate`
     *  > 128 - [16..143]  `principal`
     *  > 032 - [144..175] `loanStart`
     *  > 032 - [176..207] `loanClose`
     *  > 016 - [208..255] unused space
     */
    function initLoanContract(
        bytes32 _contractTerms,
        address _collateralAddress,
        uint256 _collateralId,
        bytes calldata _borrowerSignature
    ) external payable {
        // Verify loan terms
        _verifyTermsExpiry(_contractTerms);

        uint32 _now = __toUint32(block.timestamp);
        _verifyDuration(_contractTerms, _now);

        uint256 _principal = msg.value;
        _verifyPrincipal(_contractTerms, _principal);

        // Verify borrower participation
        IERC721Metadata _collateralToken = IERC721Metadata(_collateralAddress);
        address _borrower = _collateralToken.ownerOf(_collateralId);

        if (
            _borrower !=
            __recoverSigner(
                _contractTerms,
                _collateralAddress,
                _collateralId,
                getCollateralNonce(_collateralAddress, _collateralId),
                _borrowerSignature
            )
        ) revert InvalidParticipant({account: _borrower});

        // Add debt ID to collateral mapping
        debtIds[_collateralAddress][_collateralId].push(totalDebts);
        __setLoanAgreement(_now, _borrower, _contractTerms);

        // Transfer collateral to collateral vault.
        // The collateral ID and address will be mapped within
        // the loan collateral vault to the debt ID.
        _collateralToken.safeTransferFrom(
            _borrower,
            collateralVault,
            _collateralId,
            abi.encodePacked(_collateralAddress)
        );

        // Transfer funds to borrower
        (bool _success, ) = _borrower.call{value: _principal}("");
        if (!_success) revert FailedFundsTransfer();

        // Mint debt ALC debt tokens for borrower and lender.
        // This will grant the borrower recal access control
        // of the collateral following full loan repayment.
        anzaToken.mint(
            msg.sender,
            totalDebts * 2,
            _principal,
            _collateralToken.tokenURI(_collateralId),
            abi.encodePacked(_borrower, totalDebts)
        );

        // Emit initialization event
        emit LoanContractInitialized(
            _collateralAddress,
            _collateralId,
            totalDebts
        );

        // Setup for next debt ID
        totalDebts += 1;
    }

    function mintReplica(uint256 _debtId) external {
        address _borrower = msg.sender;

        if (_borrower != borrower(_debtId))
            revert InvalidParticipant(_borrower);

        anzaToken.mint(
            _borrower,
            (_debtId * 2) + 1,
            1,
            "",
            abi.encodePacked(_borrower, _debtId)
        );
    }

    function loanState(
        uint256 _debtId
    ) public view returns (uint256 _loanState) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint8 __loanState;

        assembly {
            __loanState := and(_contractTerms, _LOAN_STATE_MAP_)
        }

        unchecked {
            _loanState = __loanState;
        }
    }

    function firInterval(
        uint256 _debtId
    ) public view returns (uint256 _firInterval) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint8 __firInterval;

        assembly {
            __firInterval := shr(4, and(_contractTerms, _FIR_INTERVAL_MAP_))
        }

        unchecked {
            _firInterval = __firInterval;
        }
    }

    function fixedInterestRate(
        uint256 _debtId
    ) public view returns (uint256 _fixedInterestRate) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        bytes32 __fixedInterestRate;

        assembly {
            __fixedInterestRate := shr(8, and(_contractTerms, _FIR_MAP_))
        }

        unchecked {
            _fixedInterestRate = uint256(__fixedInterestRate);
        }
    }

    function loanLastChecked(uint256 _debtId) external view returns (uint256) {
        return loanStart(_debtId);
    }

    function loanStart(
        uint256 _debtId
    ) public view returns (uint256 _loanStart) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint32 __loanStart;

        assembly {
            __loanStart := shr(16, and(_contractTerms, _LOAN_START_MAP_))
        }

        unchecked {
            _loanStart = __loanStart;
        }
    }

    function loanDuration(
        uint256 _debtId
    ) public view returns (uint256 _loanDuration) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint32 __loanDuration;

        assembly {
            __loanDuration := shr(48, and(_contractTerms, _LOAN_DURATION_MAP_))
        }

        unchecked {
            _loanDuration = __loanDuration;
        }
    }

    function loanClose(
        uint256 _debtId
    ) public view returns (uint256 _loanClose) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint32 __loanClose;

        assembly {
            __loanClose := add(
                shr(16, and(_contractTerms, _LOAN_START_MAP_)),
                shr(48, and(_contractTerms, _LOAN_DURATION_MAP_))
            )
        }

        unchecked {
            _loanClose = __loanClose;
        }
    }

    function borrower(uint256 _debtId) public view returns (address _borrower) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];

        assembly {
            _borrower := shr(80, and(_contractTerms, _BORROWER_MAP_))
        }
    }

    function lenderRoyalties(
        uint256 _debtId
    ) public view returns (uint256 _lenderRoyalties) {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];

        assembly {
            _lenderRoyalties := shr(
                88,
                and(_contractTerms, _LENDER_ROYALTIES_MAP_)
            )
        }
    }

    function totalFirIntervals(
        uint256 _debtId,
        uint256 _seconds
    ) public view returns (uint256) {
        if (_checkLoanExpired(_debtId)) revert InactiveLoanState(_debtId);

        uint256 _firInterval = firInterval(_debtId);

        // _SECONDLY_
        if (_firInterval == 0) {
            return _seconds;
        }
        // _MINUTELY_
        else if (_firInterval == 1) {
            return _seconds / _MINUTELY_MULTIPLIER_;
        }
        // _HOURLY_
        else if (_firInterval == 2) {
            return _seconds / _HOURLY_MULTIPLIER_;
        }
        // _DAILY_
        else if (_firInterval == 3) {
            return _seconds / _DAILY_MULTIPLIER_;
        }
        // _WEEKLY_
        else if (_firInterval == 4) {
            return _seconds / _WEEKLY_MULTIPLIER_;
        }
        // _2_WEEKLY_
        else if (_firInterval == 5) {
            return _seconds / _2_WEEKLY_MULTIPLIER_;
        }
        // _4_WEEKLY_
        else if (_firInterval == 6) {
            return _seconds / _4_WEEKLY_MULTIPLIER_;
        }
        // _6_WEEKLY_
        else if (_firInterval == 7) {
            return _seconds / _6_WEEKLY_MULTIPLIER_;
        }
        // _8_WEEKLY_
        else if (_firInterval == 8) {
            return _seconds / _8_WEEKLY_MULTIPLIER_;
        }
        // _360_DAILY_
        else if (_firInterval == 9) {
            return _seconds / _360_DAILY_MULTIPLIER_;
        }
        // _365_DAILY_
        else if (_firInterval == 10) {
            return _seconds / _365_DAILY_MULTIPLIER_;
        }

        revert InvalidLoanParameter(_FIR_INTERVAL_ERROR_ID_);
    }

    /*
     * @dev Updates loan state.
     */
    function updateLoanState(
        uint256 _debtId
    ) external onlyRole(Roles._TREASURER_) {
        if (!checkLoanActive(_debtId)) {
            console.log("Inactive loan");
            revert InactiveLoanState(_debtId);
        }

        // Loan defaulted
        if (_checkLoanExpired(_debtId)) {
            console.log("Expired loan");
            __updateLoanTimes(_debtId);
            __setLoanState(_debtId, _DEFAULT_STATE_);
        }
        // Loan fully paid off
        else if (anzaToken.totalSupply(_debtId * 2) <= 0) {
            console.log("Paid loan");
            __setLoanState(_debtId, _PAID_STATE_);
        }
        // Loan active and interest compounding
        else if (loanState(_debtId) == _ACTIVE_STATE_) {
            console.log("Active loan");
            __updateLoanTimes(_debtId);
        }
        // Loan no longer in grace period
        else if (!_checkGracePeriod(_debtId)) {
            console.log("Newly active loan");
            __setLoanState(_debtId, _ACTIVE_STATE_);
            __updateLoanTimes(_debtId);
        }
    }

    /*
     * @dev Updates borrower.
     */
    function updateBorrower(
        uint256 _debtId,
        address _newBorrower
    ) external onlyRole(Roles._TREASURER_) {
        if (!checkLoanActive(_debtId)) {
            console.log("Inactive loan");
            revert InactiveLoanState(_debtId);
        }

        // Loan defaulted
        if (_checkLoanExpired(_debtId)) {
            console.log("Expired loan");
            __updateLoanTimes(_debtId);
            __setLoanState(_debtId, _DEFAULT_STATE_);
        }
        // Loan fully paid off
        else if (anzaToken.totalSupply(_debtId * 2) <= 0) {
            console.log("Paid loan");
            __setLoanState(_debtId, _PAID_STATE_);
        }
        // // Loan active and interest compounding
        // else if (loanState(_debtId) == _ACTIVE_STATE_) {
        //     console.log("Active loan");
        // }
        // Loan no longer in grace period
        else if (!_checkGracePeriod(_debtId)) {
            console.log("Newly active loan");
            __setLoanState(_debtId, _ACTIVE_STATE_);
            __setBorrower(_debtId, _newBorrower);
        } else {
            __setBorrower(_debtId, _newBorrower);
        }
    }

    function verifyLoanActive(uint256 _debtId) public view {
        if (!checkLoanActive(_debtId)) revert InactiveLoanState(_debtId);
    }

    function checkLoanActive(uint256 _debtId) public view returns (bool) {
        return
            loanState(_debtId) >= _ACTIVE_GRACE_STATE_ &&
            loanState(_debtId) <= _ACTIVE_STATE_;
    }

    function _checkGracePeriod(uint256 _debtId) internal view returns (bool) {
        return loanStart(_debtId) > block.timestamp;
    }

    function _checkLoanExpired(uint256 _debtId) internal view returns (bool) {
        return
            anzaToken.totalSupply(_debtId * 2) > 0 &&
            loanClose(_debtId) <= block.timestamp;
    }

    function _verifyTermsExpiry(bytes32 _contractTerms) internal pure {
        uint32 _termsExpiry;

        assembly {
            mstore(0x1b, _contractTerms)
            _termsExpiry := mload(0)
        }

        unchecked {
            if (_termsExpiry < _SECONDS_PER_24_MINUTES_RATIO_SCALED_) {
                revert InvalidLoanParameter(_TIME_EXPIRY_ERROR_ID_);
            }
        }
    }

    function _verifyDuration(
        bytes32 _contractTerms,
        uint32 _loanStart
    ) internal pure {
        uint32 _gracePeriod;
        uint32 _duration;

        assembly {
            // Get packed grace period
            mstore(0x13, _contractTerms)
            _gracePeriod := mload(0)

            // Get packed duration
            mstore(0x17, _contractTerms)
            _duration := mload(0)
        }

        unchecked {
            if (
                uint256(_duration) == 0 ||
                (uint256(_loanStart) +
                    uint256(_duration) +
                    uint256(_gracePeriod)) >
                type(uint32).max
            ) {
                revert InvalidLoanParameter(_DURATION_ERROR_ID_);
            }
        }
    }

    function _verifyPrincipal(
        bytes32 _contractTerms,
        uint256 _amount
    ) internal pure {
        uint128 _principal;

        assembly {
            mstore(0x03, _contractTerms)
            _principal := mload(0)
        }

        if (_principal == 0 || _principal != _amount)
            revert InvalidLoanParameter(_PRINCIPAL_ERROR_ID_);
    }

    function __setLoanAgreement(
        uint32 _now,
        address _borrower,
        bytes32 _contractTerms
    ) private {
        bytes32 _loanAgreement;

        assembly {
            // Get packed fixed interest rate
            mstore(0x01, _contractTerms)
            let _fixedInterestRate := mload(0)

            // Get packed grace period
            mstore(0x14, _contractTerms)
            let _gracePeriod := mload(0)

            // Get packed duration
            mstore(0x18, _contractTerms)
            let _duration := mload(0)

            // Get packed lender royalties
            mstore(0x1f, _contractTerms)
            let _lenderTerms := mload(0)

            // Shif left to make space for loan state
            mstore(0x20, shl(4, _contractTerms))

            // Pack loan state (uint4)
            switch _duration
            case 0 {
                mstore(
                    0x20,
                    xor(
                        and(_LOAN_STATE_MASK_, mload(0x20)),
                        and(_LOAN_STATE_MAP_, _ACTIVE_STATE_)
                    )
                )
            }
            default {
                mstore(
                    0x20,
                    xor(
                        and(_LOAN_STATE_MASK_, mload(0x20)),
                        and(_LOAN_STATE_MAP_, _ACTIVE_GRACE_STATE_)
                    )
                )
            }

            // Pack fir interval (uint4)
            // Already performed and not needed.

            // Pack fixed interest rate (uint8)
            mstore(
                0x20,
                xor(
                    and(_FIR_MASK_, mload(0x20)),
                    and(_FIR_MAP_, shl(8, _fixedInterestRate))
                )
            )

            // Pack loan start time (uint32)
            mstore(
                0x20,
                xor(
                    and(_LOAN_START_MASK_, mload(0x20)),
                    and(_LOAN_START_MAP_, shl(16, add(_now, _gracePeriod)))
                )
            )

            // Pack loan duration time (uint32)
            mstore(
                0x20,
                xor(
                    and(_LOAN_DURATION_MASK_, mload(0x20)),
                    and(_LOAN_DURATION_MAP_, shl(56, _duration))
                )
            )

            // Pack borrower (address)
            mstore(
                0x20,
                xor(
                    and(_BORROWER_MASK_, mload(0x20)),
                    and(_BORROWER_MAP_, shl(80, _borrower))
                )
            )

            // Pack lender royalties (uint8)
            mstore(
                0x20,
                xor(
                    and(_LENDER_ROYALTIES_MASK_, mload(0x20)),
                    and(_LENDER_ROYALTIES_MAP_, shl(240, _lenderTerms))
                )
            )

            // Cleanup
            mstore(0x20, and(_CLEANUP_MASK_, mload(0x20)))

            _loanAgreement := mload(0x20)
        }

        __packedDebtTerms[totalDebts] = _loanAgreement;
    }

    function __setLoanState(uint256 _debtId, uint8 _newLoanState) private {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        uint8 _oldLoanState;

        assembly {
            _oldLoanState := and(_LOAN_STATE_MAP_, _contractTerms)

            // If the loan states are the same, do nothing
            if eq(_oldLoanState, _newLoanState) {
                revert(0, 0)
            }

            mstore(0x20, _contractTerms)

            mstore(
                0x20,
                xor(
                    and(_LOAN_STATE_MASK_, mload(0x20)),
                    and(_LOAN_STATE_MAP_, _newLoanState)
                )
            )

            _contractTerms := mload(0x20)
        }

        __packedDebtTerms[_debtId] = _contractTerms;

        emit LoanStateChanged(_debtId, _newLoanState, _oldLoanState);
    }

    function __setBorrower(uint256 _debtId, address _newBorrower) private {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];
        address _oldBorrower;

        assembly {
            _oldBorrower := and(_BORROWER_MAP_, _contractTerms)

            // If the loan states are the same, do nothing
            if eq(_oldBorrower, _newBorrower) {
                revert(0, 0)
            }

            mstore(0x20, _contractTerms)

            mstore(
                0x20,
                xor(
                    and(_BORROWER_MASK_, mload(0x20)),
                    and(_BORROWER_MAP_, shl(80, _newBorrower))
                )
            )

            _contractTerms := mload(0x20)
        }

        __packedDebtTerms[_debtId] = _contractTerms;

        emit LoanBorrowerChanged(_debtId, _newBorrower, _oldBorrower);
    }

    function __updateLoanTimes(uint256 _debtId) private {
        bytes32 _contractTerms = __packedDebtTerms[_debtId];

        assembly {
            let _loanState := and(_LOAN_STATE_MAP_, _contractTerms)

            // If loan state is beyond active, do nothing
            if gt(_loanState, _ACTIVE_STATE_) {
                revert(0, 0)
            }

            let _now := timestamp()
            mstore(0x20, _contractTerms)

            // Store loan close time
            let _loanClose := add(
                shr(16, and(_LOAN_START_MAP_, _contractTerms)),
                shr(48, and(_LOAN_DURATION_MAP_, _contractTerms))
            )

            // Update loan last checked. This could be a transition from
            // loan start to loan last checked if it is the first time this
            // condition is executed.
            mstore(
                0x20,
                xor(
                    and(_LOAN_START_MASK_, mload(0x20)),
                    and(_LOAN_START_MAP_, shl(16, _now))
                )
            )

            // Update loan duration
            mstore(
                0x20,
                xor(
                    and(_LOAN_DURATION_MASK_, mload(0x20)),
                    and(_LOAN_DURATION_MAP_, shl(48, sub(_loanClose, _now)))
                )
            )

            _contractTerms := mload(0x20)
        }

        __packedDebtTerms[_debtId] = _contractTerms;
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v2.5._
     */
    function __toUint32(uint256 value) private pure returns (uint32) {
        require(
            value <= type(uint32).max,
            "SafeCast: value doesn't fit in 32 bits"
        );
        return uint32(value);
    }

    function __recoverSigner(
        bytes32 _contractTerms,
        address _collateralAddress,
        uint256 _collateralId,
        uint256 _collateralNonce,
        bytes memory _signature
    ) private pure returns (address) {
        bytes32 _message = __prefixed(
            keccak256(
                abi.encode(
                    _contractTerms,
                    _collateralAddress,
                    _collateralId,
                    _collateralNonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = __splitSignature(_signature);

        return ecrecover(_message, v, r, s);
    }

    function __prefixed(bytes32 _hash) private pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)
            );
    }

    function __splitSignature(
        bytes memory _signature
    ) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
    }
}
