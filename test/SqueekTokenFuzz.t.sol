// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @notice Stateless property tests over the token's arithmetic at its edges.
/// forge-config: default.fuzz.runs = 1000
contract SqueekTokenFuzzTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    SqueekToken token;
    address deployer = address(0xFAC7);

    function setUp() public {
        vm.prank(deployer);
        token = new SqueekToken();
    }

    function _notZero(address a) private pure returns (address) {
        return a == address(0) ? address(1) : a;
    }

    // ---------------------------------------------------------------- transfer

    function testFuzz_transferMovesExactly(address to, uint256 seed, uint256 amount) public {
        to = _notZero(to);
        uint256 funded = bound(seed, 0, SUPPLY);
        address from = address(0xF00D);
        vm.prank(deployer);
        token.transfer(from, funded);
        amount = bound(amount, 0, funded);

        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));

        if (to == from) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferOverBalanceReverts(address to, uint256 funded, uint256 excess) public {
        to = _notZero(to);
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - funded);
        address from = address(0xF00D);
        vm.prank(deployer);
        token.transfer(from, funded);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, from, funded, funded + excess));
        token.transfer(to, funded + excess);
        assertEq(token.balanceOf(from), funded);
    }

    function testFuzz_transferToZeroAlwaysReverts(uint256 amount) public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function testFuzz_zeroValueTransferFromAnyoneSucceeds(address from, address to) public {
        to = _notZero(to);
        vm.prank(from);
        assertTrue(token.transfer(to, 0));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalances(address a, address b, uint256 amount) public {
        a = _notZero(a);
        b = _notZero(b);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(a, amount);
        uint256 aStart = token.balanceOf(a);
        uint256 bStart = token.balanceOf(b);
        vm.prank(a);
        token.transfer(b, amount);
        vm.prank(b);
        token.transfer(a, amount);
        assertEq(token.balanceOf(a), aStart);
        assertEq(token.balanceOf(b), bStart);
    }

    function testFuzz_splitEqualsWhole(address to, uint256 amount, uint256 cut) public {
        to = _notZero(to);
        vm.assume(to != deployer);
        amount = bound(amount, 0, SUPPLY);
        cut = bound(cut, 0, amount);
        vm.startPrank(deployer);
        token.transfer(to, cut);
        token.transfer(to, amount - cut);
        vm.stopPrank();
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }

    function testFuzz_sequenceConservesSupply(uint256[8] memory amounts, uint8 pattern) public {
        address[4] memory actors = [deployer, address(0xA1), address(0xA2), address(0xA3)];
        for (uint256 i = 0; i < amounts.length; i++) {
            address from = actors[(pattern >> (i * 2)) & 3];
            address to = actors[(uint256(pattern) + i + 1) & 3];
            uint256 bal = token.balanceOf(from);
            uint256 amount = bound(amounts[i], 0, bal);
            vm.prank(from);
            token.transfer(to, amount);
        }
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- approve

    function testFuzz_approveSetsExactly(address owner, address spender, uint256 value) public {
        spender = _notZero(spender);
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        assertEq(token.allowance(owner, spender), value);
    }

    function testFuzz_approveOverwrites(address spender, uint256 first, uint256 second) public {
        spender = _notZero(spender);
        vm.startPrank(deployer);
        token.approve(spender, first);
        token.approve(spender, second);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), second);
    }

    function testFuzz_approveZeroSpenderAlwaysReverts(address owner, uint256 value) public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidSpender.selector, address(0)));
        token.approve(address(0), value);
    }

    function testFuzz_approveDoesNotMoveBalance(address spender, uint256 value) public {
        spender = _notZero(spender);
        vm.prank(deployer);
        token.approve(spender, value);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), spender == deployer ? SUPPLY : 0);
    }

    // ---------------------------------------------------------------- transferFrom

    function testFuzz_transferFromDecrementsAllowance(address spender, address to, uint256 allowed, uint256 amount)
        public
    {
        spender = _notZero(spender);
        to = _notZero(to);
        allowed = bound(allowed, 0, type(uint256).max - 1); // the max is the unlimited sentinel
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);

        uint256 toBefore = token.balanceOf(to);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, to, amount));

        assertEq(token.allowance(deployer, spender), allowed - amount);
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), toBefore + amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
    }

    function testFuzz_transferFromOverAllowanceReverts(address spender, uint256 allowed, uint256 excess) public {
        spender = _notZero(spender);
        allowed = bound(allowed, 0, type(uint256).max - 2);
        excess = bound(excess, 1, type(uint256).max - 1 - allowed);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, spender, allowed, allowed + excess)
        );
        token.transferFrom(deployer, address(0xB0B), allowed + excess);
        assertEq(token.allowance(deployer, spender), allowed);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function testFuzz_transferFromOverBalanceRevertsAndKeepsAllowance(uint256 funded, uint256 excess) public {
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - 1 - funded);
        address owner = address(0x0A);
        address spender = address(0x0B);
        vm.prank(deployer);
        token.transfer(owner, funded);
        vm.prank(owner);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, owner, funded, funded + excess)
        );
        token.transferFrom(owner, address(0xB0B), funded + excess);
        assertEq(token.allowance(owner, spender), type(uint256).max - 1);
        assertEq(token.balanceOf(owner), funded);
    }

    function testFuzz_infiniteAllowanceIsSticky(address spender, uint256 amount) public {
        spender = _notZero(spender);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, address(0xB0B), amount);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(address(0xB0B)), amount);
    }

    function testFuzz_transferFromWithoutApprovalRevertsForAnyPositiveValue(address spender, uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, spender, 0, amount));
        token.transferFrom(deployer, address(0xB0B), amount);
    }

    function testFuzz_transferFromToZeroRevertsAndKeepsAllowance(address spender, uint256 allowed, uint256 amount)
        public
    {
        spender = _notZero(spender);
        vm.prank(deployer);
        token.approve(spender, allowed);
        amount = bound(amount, 0, allowed);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), allowed);
    }

    // ---------------------------------------------------------------- supply

    function testFuzz_noCallGrowsSupply(bytes4 selector, address a, uint256 v) public {
        vm.prank(deployer);
        token.transfer(a == address(0) ? address(1) : a, 1);
        (bool ok,) = address(token).call(abi.encodeWithSelector(selector, a, v));
        ok;
        assertEq(token.totalSupply(), SUPPLY);
        assertLe(token.balanceOf(a), SUPPLY);
    }
}
