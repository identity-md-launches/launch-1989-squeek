// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @notice Stands in for the launch factory: deploys the token and forwards the swarm's share in the
/// same call, the way `launchCustom` does in one transaction. Only the test drives it.
contract FactoryProbe {
    SqueekToken public token;

    function deployAndForward(address distributor, uint256 swarm, address remainderTo)
        external
        returns (uint256 mintedHere, uint256 forwarded, uint256 remainder)
    {
        token = new SqueekToken();
        mintedHere = token.balanceOf(address(this));
        require(token.transfer(distributor, swarm), "distributor transfer returned false");
        forwarded = token.balanceOf(distributor);
        require(token.transfer(remainderTo, mintedHere - swarm), "remainder transfer returned false");
        remainder = token.balanceOf(remainderTo);
    }
}

/// @notice A contract with no fallback and no receive, so nothing the token might send it could land.
contract NoReceiver {}

/// @notice Edge cases and failure paths of the SQUEEK token: zero, one wei, the whole supply, the
/// maximum, the same call twice, and callers the code did not assume.
contract SqueekTokenEdgesTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    SqueekToken token;
    address deployer = address(0xFAC7);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new SqueekToken();
    }

    // ---------------------------------------------------------------- supply and metadata

    function test_totalSupplyConstantMatchesStorage() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_supplyIsMintedToMsgSenderNotTxOrigin() public {
        address origin = address(0x0121);
        address sender = address(0x5E4D);
        vm.prank(sender, origin);
        SqueekToken fresh = new SqueekToken();
        assertEq(fresh.balanceOf(sender), SUPPLY, "supply must land on msg.sender");
        assertEq(fresh.balanceOf(origin), 0, "tx.origin must receive nothing");
    }

    function test_eachDeploymentIsIndependent() public {
        vm.prank(alice);
        SqueekToken second = new SqueekToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0, "a second deployment must not touch the first");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_nobodyElseHoldsAnythingAtDeployment() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_runtimeFitsEip170AndHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------- transfer edges

    function test_zeroValueTransferSucceedsAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, alice, 0);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_zeroValueTransferFromEmptyAccountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_oneWeiTransfer() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_wholeSupplyTransferLeavesDeployerEmpty() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_oneWeiOverBalanceReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_maxValueTransferReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_emptyAccountCannotSendOneWei() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_selfTransferKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        vm.prank(deployer);
        token.transfer(deployer, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferOverBalanceReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(deployer, SUPPLY + 1);
    }

    function test_transferToZeroRevertsEvenForZeroValue() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferToTokenItselfIsAllowedAndStuck() public {
        // Nothing privileged exists to recover it; the test only pins that the arithmetic is exact.
        vm.prank(deployer);
        token.transfer(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.balanceOf(deployer), SUPPLY - 5);
    }

    function test_transferToContractWithoutReceiverSucceeds() public {
        NoReceiver sink = new NoReceiver();
        vm.prank(deployer);
        assertTrue(token.transfer(address(sink), 7));
        assertEq(token.balanceOf(address(sink)), 7);
    }

    function test_sameTransferTwiceMovesTwice() public {
        vm.startPrank(deployer);
        token.transfer(alice, 10);
        token.transfer(alice, 10);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 20);
        assertEq(token.balanceOf(deployer), SUPPLY - 20);
    }

    function test_failedTransferLeavesNoTrace() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, alice, 10, 11));
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_chainOfTransfersConservesSupply() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000);
        vm.prank(alice);
        token.transfer(bob, 600);
        vm.prank(bob);
        token.transfer(carol, 599);
        vm.prank(carol);
        token.transfer(deployer, 1);
        assertEq(token.balanceOf(alice), 400);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(carol), 598);
        assertEq(token.balanceOf(deployer), SUPPLY - 999);
        assertEq(
            token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol), SUPPLY
        );
    }

    // ---------------------------------------------------------------- approve edges

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(alice, 100);
        token.approve(alice, 30);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 30);
    }

    function test_approveZeroResetsAndEmits() public {
        vm.startPrank(deployer);
        token.approve(alice, 100);
        vm.expectEmit(true, true, false, true);
        emit Approval(deployer, alice, 0);
        assertTrue(token.approve(alice, 0));
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_approveNeedsNoBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(bob, SUPPLY));
        assertEq(token.allowance(alice, bob), SUPPLY);
        // The allowance is a promise the balance cannot keep: spending it reverts on balance.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, carol, 1);
        assertEq(token.allowance(alice, bob), SUPPLY, "a failed transferFrom must not consume allowance");
    }

    function test_approveSelfIsAllowedAndSpendable() public {
        vm.startPrank(deployer);
        token.approve(deployer, 50);
        token.transferFrom(deployer, alice, 50);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 50);
        assertEq(token.allowance(deployer, deployer), 0);
    }

    function test_approveZeroSpenderRevertsForZeroValueToo() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_allowancesAreIndependentPerSpender() public {
        vm.startPrank(deployer);
        token.approve(alice, 10);
        token.approve(bob, 20);
        vm.stopPrank();
        vm.prank(alice);
        token.transferFrom(deployer, carol, 10);
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.allowance(deployer, bob), 20, "another spender's allowance must be untouched");
    }

    function test_allowanceIsDirectional() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        assertEq(token.allowance(alice, deployer), 0);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, bob, 1);
    }

    // ---------------------------------------------------------------- transferFrom edges

    function test_transferFromWithoutApprovalReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromBySelfStillNeedsAllowance() public {
        // msg.sender == from is not a shortcut: the owner must approve itself.
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromZeroValueWithoutApprovalSucceeds() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, bob, 0);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromExactAllowanceThenOneMoreReverts() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.startPrank(alice);
        token.transferFrom(deployer, bob, 10);
        assertEq(token.allowance(deployer, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 10);
    }

    function test_transferFromSpentInPieces() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.startPrank(alice);
        token.transferFrom(deployer, bob, 4);
        token.transferFrom(deployer, carol, 6);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 4);
        assertEq(token.balanceOf(carol), 6);
    }

    function test_transferFromToZeroRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 5);
        assertEq(token.allowance(deployer, alice), 10);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromOverBalanceRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, carol, 11);
        assertEq(token.allowance(alice, bob), 100);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_transferFromToOwnerItself() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        token.transferFrom(deployer, deployer, 10);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, alice), 0, "allowance is consumed even on a round trip");
    }

    function test_transferFromToSpender() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        token.transferFrom(deployer, alice, 10);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_transferFromEmitsTransferNotApproval() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        vm.recordLogs();
        token.transferFrom(deployer, bob, 3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event per transferFrom");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(address(uint160(uint256(logs[0].topics[1]))), deployer);
        assertEq(address(uint160(uint256(logs[0].topics[2]))), bob);
        assertEq(abi.decode(logs[0].data, (uint256)), 3);
    }

    function test_infiniteAllowanceSpendsWholeBalanceButNotMore() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.startPrank(alice);
        token.transferFrom(deployer, bob, SUPPLY);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, deployer, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
    }

    function test_transferFromFromZeroAddressMovesNothing() public {
        // The code does not reject `from == address(0)`. With value 0 the call goes through and
        // emits Transfer(0x0, to, 0); with any value it reverts on allowance. Either way no balance
        // and no supply changes. The event oddity is reported, not blessed, in .imd-findings.json.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), bob, 1);

        vm.prank(alice);
        token.transferFrom(address(0), bob, 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- no privileged surface

    function test_etherIsRefused() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "the token must not accept ether");
        (ok,) = address(token).call{value: 1}(abi.encodeWithSelector(token.transfer.selector, alice, 0));
        assertFalse(ok, "non-payable functions must refuse value");
        assertEq(address(token).balance, 0);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token).call("");
        assertFalse(ok, "no fallback");
    }

    function test_noAdminEntrypointsExist() public {
        string[20] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "paused()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "freeze(address)",
            "seize(address)",
            "setFee(uint256)",
            "setTransfersEnabled(bool)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)",
            "increaseAllowance(address,uint256)"
        ];
        vm.prank(deployer);
        token.transfer(alice, 1_000);
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(alice);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 1_000);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1_000), "the holder can still transfer");
    }

    function test_deployerHasNoPowerOverHolders() public {
        vm.prank(deployer);
        token.transfer(alice, 100);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100);
    }

    // ---------------------------------------------------------------- launch flows

    function test_launchFlowsArriveWholeInOneTransaction() public {
        FactoryProbe factory = new FactoryProbe();
        address distributor = address(0xD157);
        address requester = address(0x5E9E);
        uint256 swarm = SUPPLY / 10;
        (uint256 minted, uint256 forwarded, uint256 remainder) = factory.deployAndForward(distributor, swarm, requester);
        SqueekToken launched = factory.token();
        assertEq(minted, SUPPLY, "the factory must receive the whole supply in its own call");
        assertEq(forwarded, swarm, "the swarm's share arrived short");
        assertEq(remainder, SUPPLY - swarm, "the remainder arrived short");
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);

        // A claim leaves the distributor whole again.
        address claimant = address(0xC1A1);
        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm));
        assertEq(launched.balanceOf(claimant), swarm);
        assertEq(launched.balanceOf(distributor), 0);
    }

    function test_poolStylePullMovesExactly() public {
        // A pool manager settles by transferFrom after an approval; the amount pulled is exact.
        address poolManager = address(0x9001);
        vm.prank(deployer);
        token.approve(poolManager, SUPPLY / 2);
        vm.prank(poolManager);
        assertTrue(token.transferFrom(deployer, poolManager, SUPPLY / 2));
        assertEq(token.balanceOf(poolManager), SUPPLY / 2);
        assertEq(token.allowance(deployer, poolManager), 0);
        // A trader sells back into the pool and buys out of it: each leg exact.
        address trader = address(0x7A4D);
        vm.prank(poolManager);
        token.transfer(trader, 1e18);
        assertEq(token.balanceOf(trader), 1e18);
        vm.prank(trader);
        token.transfer(poolManager, 1e18);
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), SUPPLY / 2);
    }
}
