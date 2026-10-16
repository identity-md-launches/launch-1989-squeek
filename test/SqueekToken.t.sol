// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

contract SqueekTokenTest is Test {
    SqueekToken token;
    address deployer = address(0xFAC7);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new SqueekToken();
    }

    function test_metadata() public view {
        assertEq(token.name(), "squeek");
        assertEq(token.symbol(), "SQUEEK");
        assertEq(token.decimals(), 18);
    }

    function test_supplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(deployer), 1_000_000_000e18);
    }

    function test_constructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), 1_000_000_000e18);
        new SqueekToken();
    }

    function test_transfer() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, alice, 100);
        assertTrue(token.transfer(alice, 100));
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(deployer), token.totalSupply() - 100);
    }

    function test_transferInsufficientReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferToZeroReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, false, true);
        emit Approval(deployer, alice, 50);
        token.approve(alice, 50);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 30);
        assertEq(token.balanceOf(bob), 30);
        assertEq(token.allowance(deployer, alice), 20);
    }

    function test_infiniteAllowanceNotDecreased() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 30);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_transferFromOverAllowanceReverts() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, alice, 10, 11));
        token.transferFrom(deployer, bob, 11);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekToken.InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_noMintEntrypoint() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
        assertEq(token.totalSupply(), 1_000_000_000e18);
    }

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, token.totalSupply());
        vm.prank(deployer);
        token.transfer(to, amount);
        uint256 sum = to == deployer ? token.balanceOf(deployer) : token.balanceOf(deployer) + token.balanceOf(to);
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(to), to == deployer ? token.totalSupply() : amount);
    }
}
