// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";

import "../contracts/domain/LoanContractRoles.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ILoanNotary, IListingNotary, IRefinanceNotary} from "../contracts/interfaces/ILoanNotary.sol";
import {IERC1155Events} from "./interfaces/IERC1155Events.t.sol";
import {IAccessControlEvents} from "./interfaces/IAccessControlEvents.t.sol";
import {ICollateralVault} from "../contracts/interfaces/ICollateralVault.sol";
import {LoanContract} from "../contracts/LoanContract.sol";
import {CollateralVault} from "../contracts/CollateralVault.sol";
import {LoanTreasurey} from "../contracts/LoanTreasurey.sol";
import {DemoToken} from "../contracts/utils/DemoToken.sol";
import {AnzaToken} from "../contracts/token/AnzaToken.sol";
import {AnzaDebtStorefront} from "../contracts/AnzaDebtStorefront.sol";
import {LibLoanNotary as Signing} from "../contracts/libraries/LibLoanNotary.sol";

error TryCatchErr(bytes err);

abstract contract Utils {
    /* ------------------------------------------------ *
     *                  Loan Terms                      *
     * ------------------------------------------------ */
    uint8 public constant _FIR_INTERVAL_ = 14;
    uint8 public constant _FIXED_INTEREST_RATE_ = 10; // 0.10
    uint8 public constant _IS_FIXED_ = 0; // false
    uint8 public constant _COMMITAL_ = 25; // 0.25
    uint256 public constant _PRINCIPAL_ = 10000000000; // WEI
    uint32 public constant _GRACE_PERIOD_ = 86400;
    uint32 public constant _DURATION_ = 1209600;
    uint32 public constant _TERMS_EXPIRY_ = 86400;
    uint8 public constant _LENDER_ROYALTIES_ = 10;
    // To calc max price of loan with compounding interest:
    // principal = 10
    // fixedInterestRate = 5
    // duration = 62208000
    // firInterval = 60 * 60 * 24
    // compoundingPeriods = 1
    // timePeriodOfLoan = duration / firInterval
    //
    // principal * (1 + (fixedInterestRate/100 / compoundingPeriods)) ^ (compoundingPeriods * timePeriodOfLoan)
    // 10 * (1 + (0.05 / 1)) ** (1 * 720)

    uint8 public constant _ALT_FIR_INTERVAL_ = 14;
    uint8 public constant _ALT_FIXED_INTEREST_RATE_ = 5; // 0.05
    uint256 public constant _ALT_PRINCIPAL_ = 4; // ETH // 226854911280625642308916404954512140970
    uint32 public constant _ALT_GRACE_PERIOD_ = 60 * 60 * 24 * 5; // 604800 (5 days)
    uint32 public constant _ALT_DURATION_ = 60 * 60 * 24 * 360 * 1; // 62208000 (1 year)
    uint32 public constant _ALT_TERMS_EXPIRY_ = 60 * 60 * 24 * 4; // 1209600 (4 days)
    uint8 public constant _ALT_LENDER_ROYALTIES_ = 10; // 0.10

    /* ------------------------------------------------ *
     *                    CONSTANTS                     *
     * ------------------------------------------------ */
    string public constant _BASE_URI_ = "https://www.a_base_uri.com/";
    string public baseURI = "https://www.demo_token_metadata_uri.com/";
    uint256 public constant collateralId = 5;

    function getTokenURI(uint256 _tokenId) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _BASE_URI_,
                    "debt-token/",
                    Strings.toString(_tokenId)
                )
            );
    }

    function getAccessControlFailMsg(
        bytes32 _role,
        address _account
    ) public pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(_account), 20),
                    " is missing role ",
                    Strings.toHexString(uint256(_role), 32)
                )
            );
    }
}

contract LoanContractHarness is LoanContract {
    constructor() LoanContract() {}

    function exposed__getTotalFirIntervals(
        uint256 _firInterval,
        uint256 _seconds
    ) public pure returns (uint256) {
        return _getTotalFirIntervals(_firInterval, _seconds);
    }
}

abstract contract Setup is Test, Utils, IERC1155Events, IAccessControlEvents {
    address public borrower = vm.envAddress("DEAD_ACCOUNT_KEY_0");
    address public treasurer = vm.envAddress("DEAD_ACCOUNT_KEY_2");
    address public collector = vm.envAddress("DEAD_ACCOUNT_KEY_3");
    address public admin = vm.envAddress("DEAD_ACCOUNT_KEY_4");
    address public lender = vm.envAddress("DEAD_ACCOUNT_KEY_5");
    address public alt_account = vm.envAddress("DEAD_ACCOUNT_KEY_9");

    uint256 public borrowerPrivKey = vm.envUint("DEAD_ACCOUNT_PRIVATE_KEY_0");
    uint256 public lenderPrivKey = vm.envUint("DEAD_ACCOUNT_PRIVATE_KEY_5");

    CollateralVault public collateralVault;
    LoanContract public loanContract;
    LoanTreasurey public loanTreasurer;
    AnzaToken public anzaToken;
    DemoToken public demoToken;

    uint256 public collateralNonce;
    bytes32 public contractTerms;
    bytes public signature;

    AnzaDebtStorefront public anzaDebtStorefront;
    Signing.DomainSeparator public listingDomainSeparator;
    Signing.DomainSeparator public refinanceDomainSeparator;

    struct ContractTerms {
        uint8 firInterval;
        uint8 fixedInterestRate;
        uint8 isFixed;
        uint8 commital;
        uint256 principal;
        uint32 gracePeriod;
        uint32 duration;
        uint32 termsExpiry;
        uint8 lenderRoyalties;
    }

    function setUp() public virtual {
        vm.deal(admin, 1 ether);
        vm.startPrank(admin);

        // Deploy AnzaToken
        anzaToken = new AnzaToken("Anza Debt Token", "ADT", "www.anza.io");

        // Deploy LoanContract
        loanContract = new LoanContract();

        // Deploy LoanTreasurey
        loanTreasurer = new LoanTreasurey();

        // Deploy CollateralVault
        collateralVault = new CollateralVault(address(anzaToken));

        // Set AnzaToken access control roles
        anzaToken.grantRole(_LOAN_CONTRACT_, address(loanContract));
        anzaToken.grantRole(_TREASURER_, address(loanTreasurer));
        anzaToken.grantRole(_COLLATERAL_VAULT_, address(collateralVault));

        // Set LoanContract access control roles
        loanContract.setAnzaToken(address(anzaToken));
        loanContract.setLoanTreasurer(address(loanTreasurer));
        loanContract.setCollateralVault(address(collateralVault));

        // Set LoanTreasurey access control roles
        loanTreasurer.setAnzaToken(address(anzaToken));
        loanTreasurer.setLoanContract(address(loanContract));
        loanTreasurer.setCollateralVault(address(collateralVault));

        // Set CollateralVault access control roles
        collateralVault.setLoanContract(address(loanContract));
        collateralVault.grantRole(_TREASURER_, address(loanTreasurer));

        vm.stopPrank();

        vm.startPrank(borrower);
        demoToken = new DemoToken();
        // demoToken = DemoToken(0x3aAde2dCD2Df6a8cAc689EE797591b2913658659);
        demoToken.approve(address(loanContract), collateralId);
        demoToken.setApprovalForAll(address(loanContract), true);

        vm.stopPrank();

        anzaDebtStorefront = new AnzaDebtStorefront(
            address(loanContract),
            address(loanTreasurer),
            address(anzaToken)
        );

        vm.startPrank(admin);
        loanTreasurer.grantRole(_DEBT_STOREFRONT_, address(anzaDebtStorefront));
        vm.stopPrank();

        listingDomainSeparator = Signing.DomainSeparator({
            name: "AnzaDebtStorefront:ListingNotary",
            version: "0",
            chainId: block.chainid,
            contractAddress: address(anzaDebtStorefront)
        });

        refinanceDomainSeparator = Signing.DomainSeparator({
            name: "AnzaDebtStorefront:RefinanceNotary",
            version: "0",
            chainId: block.chainid,
            contractAddress: address(anzaDebtStorefront)
        });
    }

    function createContractTerms()
        public
        virtual
        returns (bytes32 _contractTerms)
    {
        assembly {
            mstore(0x20, _FIR_INTERVAL_)
            mstore(0x1f, _FIXED_INTEREST_RATE_)
            mstore(0x0d, _GRACE_PERIOD_)
            mstore(0x09, _DURATION_)
            mstore(0x05, _TERMS_EXPIRY_)
            mstore(0x01, _LENDER_ROYALTIES_)

            _contractTerms := mload(0x20)
        }
    }

    function createContractTerms(
        ContractTerms memory _terms
    ) public pure virtual returns (bytes32 _contractTerms) {
        uint8 _firInterval = _terms.firInterval;
        uint8 _fixedInterestRate = _terms.fixedInterestRate;
        uint8 _isDirect = _terms.isFixed;
        uint8 _commital = _terms.commital;
        uint32 _gracePeriod = _terms.gracePeriod;
        uint32 _duration = _terms.duration;
        uint32 _termsExpiry = _terms.termsExpiry;
        uint8 _lenderRoyalties = _terms.lenderRoyalties;

        assembly {
            mstore(0x20, _firInterval)
            mstore(0x1f, _fixedInterestRate)

            if eq(_isDirect, 0x01) {
                _commital := add(0x65, _commital)
            }
            mstore(0x1e, _commital)

            mstore(0x0d, _gracePeriod)
            mstore(0x09, _duration)
            mstore(0x05, _termsExpiry)
            mstore(0x01, _lenderRoyalties)

            _contractTerms := mload(0x20)
        }
    }

    function createContractSignature(
        uint256 _principal,
        uint256 _collateralId,
        uint256 _collateralNonce,
        bytes32 _contractTerms
    ) public virtual returns (bytes memory _signature) {
        // Create message for signing
        bytes32 _message = Signing.typeDataHash(
            ILoanNotary.ContractParams({
                principal: _principal,
                contractTerms: _contractTerms,
                collateralAddress: address(demoToken),
                collateralId: _collateralId,
                collateralNonce: _collateralNonce
            }),
            Signing.DomainSeparator({
                name: "LoanContract",
                version: "0",
                chainId: block.chainid,
                contractAddress: address(loanContract)
            })
        );

        // Sign borrower's terms
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(borrowerPrivKey, _message);
        _signature = abi.encodePacked(r, s, v);
    }

    function initLoanContract(
        uint256 _debtId,
        bytes32 _contractTerms,
        bytes memory _signature
    ) public virtual returns (bool _success, bytes memory _data) {
        // Create loan contract
        vm.startPrank(lender);
        (_success, _data) = address(loanContract).call{value: _PRINCIPAL_}(
            abi.encodeWithSignature(
                "initLoanContract(uint256,bytes32,bytes)",
                _debtId,
                _contractTerms,
                _signature
            )
        );

        vm.stopPrank();

        _data = abi.encodePacked(_data);
    }

    function initLoanContract(
        uint256 _debtId,
        uint256 _principal,
        bytes32 _contractTerms,
        bytes memory _signature
    ) public virtual returns (bool _success, bytes memory _data) {
        // Create loan contract
        vm.deal(lender, _principal + (1 ether));
        vm.startPrank(lender);
        (_success, _data) = address(loanContract).call{value: _principal}(
            abi.encodeWithSignature(
                "initLoanContract(uint256,bytes32,bytes)",
                _debtId,
                _contractTerms,
                _signature
            )
        );
        vm.stopPrank();

        _data = abi.encodePacked(_data);
    }

    function initLoanContract(
        uint256 _principal,
        address _collateralAddress,
        uint256 _collateralId,
        bytes32 _contractTerms,
        bytes memory _signature
    ) public virtual returns (bool _success, bytes memory _data) {
        // Create loan contract
        vm.deal(lender, _principal);
        vm.startPrank(lender);

        (_success, _data) = address(loanContract).call{value: _principal}(
            abi.encodeWithSignature(
                "initLoanContract(address,uint256,bytes32,bytes)",
                _collateralAddress,
                _collateralId,
                _contractTerms,
                _signature
            )
        );

        vm.stopPrank();

        _data = abi.encodePacked(_data);
    }

    function initRefinanceContract(
        uint256 _price,
        uint256 _debtId,
        uint256 _termsExpiry,
        bytes32 _contractTerms,
        bytes memory _signature
    ) public returns (bool _success, bytes memory _data) {
        vm.deal(alt_account, 4 ether);
        vm.startPrank(alt_account);
        (_success, _data) = address(anzaDebtStorefront).call{value: _price}(
            abi.encodeWithSignature(
                "buyRefinance(uint256,uint256,bytes32,bytes)",
                _debtId,
                _termsExpiry,
                _contractTerms,
                _signature
            )
        );
        assertTrue(
            _success,
            "0 :: initRefinanceContract :: buyRefinance test should succeed."
        );
        vm.stopPrank();
    }

    function createLoanContract(
        uint256 _collateralId
    ) public virtual returns (bool, bytes memory) {
        bytes32 _contractTerms = createContractTerms();

        uint256 _collateralNonce = loanContract.collateralNonce(
            address(demoToken),
            _collateralId
        );

        bytes memory _signature = createContractSignature(
            _PRINCIPAL_,
            _collateralId,
            _collateralNonce,
            _contractTerms
        );

        return
            initLoanContract(
                _PRINCIPAL_,
                address(demoToken),
                _collateralId,
                _contractTerms,
                _signature
            );
    }

    function createLoanContract(
        uint256 _collateralId,
        ContractTerms memory _terms
    ) public virtual returns (bool, bytes memory) {
        uint256 _collateralNonce = loanContract.collateralNonce(
            address(demoToken),
            _collateralId
        );

        return createLoanContract(_collateralId, _collateralNonce, _terms);
    }

    function createLoanContract(
        uint256 _collateralId,
        uint256 _collateralNonce,
        ContractTerms memory _terms
    ) public virtual returns (bool, bytes memory) {
        bytes32 _contractTerms = createContractTerms(_terms);

        bytes memory _signature = createContractSignature(
            _terms.principal,
            _collateralId,
            _collateralNonce,
            _contractTerms
        );

        return
            initLoanContract(
                _terms.principal,
                address(demoToken),
                _collateralId,
                _contractTerms,
                _signature
            );
    }

    function createListingSignature(
        uint256 _sellerPrivateKey,
        IListingNotary.ListingParams memory _debtListingParams
    ) public virtual returns (bytes memory _signature) {
        bytes32 _message = Signing.typeDataHash(
            _debtListingParams,
            listingDomainSeparator
        );

        // Sign seller's listing terms
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_sellerPrivateKey, _message);
        _signature = abi.encodePacked(r, s, v);
    }

    function createRefinanceSignature(
        uint256 _sellerPrivateKey,
        IRefinanceNotary.RefinanceParams memory _debtRefinanceParams
    ) public virtual returns (bytes memory _signature) {
        bytes32 _message = Signing.typeDataHash(
            _debtRefinanceParams,
            refinanceDomainSeparator
        );

        // Sign seller's listing terms
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_sellerPrivateKey, _message);
        _signature = abi.encodePacked(r, s, v);
    }

    function refinanceDebt(
        uint256 _debtId
    ) public virtual returns (bool, bytes memory) {
        return
            refinanceDebt(
                _debtId,
                ContractTerms({
                    firInterval: _FIR_INTERVAL_,
                    fixedInterestRate: _FIXED_INTEREST_RATE_,
                    isFixed: _IS_FIXED_,
                    commital: _COMMITAL_,
                    principal: _PRINCIPAL_,
                    gracePeriod: _GRACE_PERIOD_,
                    duration: _DURATION_,
                    termsExpiry: _TERMS_EXPIRY_,
                    lenderRoyalties: _LENDER_ROYALTIES_
                })
            );
    }

    function refinanceDebt(
        uint256 _debtId,
        ContractTerms memory _terms
    ) public virtual returns (bool, bytes memory) {
        uint256 _debtListingNonce = anzaDebtStorefront.getListingNonce(_debtId);
        uint256 _termsExpiry = uint256(_TERMS_EXPIRY_);

        bytes32 _contractTerms = createContractTerms(_terms);

        bytes memory _signature = createRefinanceSignature(
            borrowerPrivKey,
            IRefinanceNotary.RefinanceParams({
                price: _terms.principal,
                debtId: _debtId,
                contractTerms: _contractTerms,
                listingNonce: _debtListingNonce,
                termsExpiry: _termsExpiry
            })
        );

        return
            initRefinanceContract(
                _terms.principal,
                _debtId,
                _termsExpiry,
                _contractTerms,
                _signature
            );
    }

    // function refinanceDebt(
    //     uint256 _debtId,
    //     ContractTerms memory _terms
    // ) public virtual returns (bool, bytes memory) {
    //     bytes32 _contractTerms = createContractTerms(_terms);

    //     ICollateralVault.Collateral memory _collateral = ICollateralVault(
    //         collateralVault
    //     ).getCollateral(_debtId);

    //     uint256 _collateralNonce = loanContract.collateralNonce(
    //         address(demoToken),
    //         _collateral.collateralId
    //     );

    //     bytes memory _signature = createContractSignature(
    //         _terms.principal,
    //         _collateral.collateralId,
    //         _collateralNonce,
    //         _contractTerms
    //     );

    //     return
    //         initLoanContract(
    //             _debtId,
    //             _terms.principal,
    //             _contractTerms,
    //             _signature
    //         );
    // }

    function mintDemoTokens(uint256 _amount) public virtual {
        vm.startPrank(borrower);
        demoToken.mint(_amount);
        vm.stopPrank();
    }
}
