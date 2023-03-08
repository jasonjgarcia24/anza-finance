// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {LibOfficerRoles as Roles, LibLoanContractMetadata as Metadata, LibLoanContractInit as Init, LibLoanContractIndexer as Indexer} from "../contracts/libraries/LibLoanContract.sol";
import {Test, LoanContractDeployer} from "./LoanContract.t.sol";

contract LoanContractTestDeployment is LoanContractDeployer {
    function testStateVars() public {
        assertEq(loanContract.arbiter(), address(loanArbiter));
    }
}

contract LoanContractTestAccessControl is LoanContractDeployer {
    function testHasRole() public {
        assertTrue(loanContract.hasRole(Roles._ADMIN_, admin));
        assertTrue(loanContract.hasRole(Roles._TREASURER_, treasurer));
        assertTrue(loanContract.hasRole(Roles._COLLECTOR_, collector));
    }

    function testDoesNotHaveRole() public {
        assertFalse(loanContract.hasRole(Roles._ADMIN_, treasurer));
        assertFalse(loanContract.hasRole(Roles._ADMIN_, collector));

        assertFalse(loanContract.hasRole(Roles._TREASURER_, admin));
        assertFalse(loanContract.hasRole(Roles._TREASURER_, collector));

        assertFalse(loanContract.hasRole(Roles._COLLECTOR_, admin));
        assertFalse(loanContract.hasRole(Roles._COLLECTOR_, treasurer));
    }

    function testGrantRole() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(Roles._ADMIN_, alt_account, admin);
        loanContract.grantRole(Roles._ADMIN_, alt_account);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(Roles._TREASURER_, alt_account, admin);
        loanContract.grantRole(Roles._TREASURER_, alt_account);

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(Roles._COLLECTOR_, alt_account, admin);
        loanContract.grantRole(Roles._COLLECTOR_, alt_account);

        vm.stopPrank();
    }

    function testCannotGrantRole() public {
        // Fail call from treasurer
        vm.startPrank(treasurer);
        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, treasurer));
        loanContract.grantRole(Roles._ADMIN_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, treasurer));
        loanContract.grantRole(Roles._TREASURER_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, treasurer));
        loanContract.grantRole(Roles._COLLECTOR_, alt_account);
        vm.stopPrank();

        // Fail call from collector
        vm.startPrank(collector);
        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, collector));
        loanContract.grantRole(Roles._ADMIN_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, collector));
        loanContract.grantRole(Roles._TREASURER_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, collector));
        loanContract.grantRole(Roles._COLLECTOR_, alt_account);
        vm.stopPrank();

        // Fail call from alt_account
        vm.startPrank(alt_account);
        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, alt_account));
        loanContract.grantRole(Roles._ADMIN_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, alt_account));
        loanContract.grantRole(Roles._TREASURER_, alt_account);

        vm.expectRevert(__getCheckRoleFailMsg(Roles._ADMIN_, alt_account));
        loanContract.grantRole(Roles._COLLECTOR_, alt_account);
        vm.stopPrank();
    }

    function __getCheckRoleFailMsg(bytes32 _role, address _account)
        private
        pure
        returns (bytes memory)
    {
        return
            bytes(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(uint160(_account), 20),
                        " is missing role ",
                        Strings.toHexString(uint256(_role), 32)
                    )
                )
            );
    }
}

contract LoanContractTestERC1155URIStorage is LoanContractDeployer {
    function testStateVars() public {
        // URI for token ID 0 is not set yet and should therefore
        // default to the baseURI
        assertEq(loanContract.uri(0), baseURI);
    }
}
