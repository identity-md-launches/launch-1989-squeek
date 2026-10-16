// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @notice Drives the token with a fixed set of actors and bounded inputs, in random order. It tries
/// the failure paths too (over-balance, over-allowance, zero receiver, zero spender) and checks in
/// place that each reverts with the exact error and changes nothing. Ghost variables record what
/// the token should hold and allow, so the invariants can compare.
contract SqueekHandler is Test {
    SqueekToken public token;
    address[] public actors;
    mapping(address => bool) public isActor;

    // Ghosts.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    uint256 public ghostMoved; // sum of every value that moved between distinct accounts
    uint256 public callsTransfer;
    uint256 public callsTransferFrom;
    uint256 public callsApprove;
    uint256 public revertsSeen;

    constructor(SqueekToken token_, address deployer, address[] memory others) {
        token = token_;
        actors.push(deployer);
        isActor[deployer] = true;
        for (uint256 i = 0; i < others.length; i++) {
            actors.push(others[i]);
            isActor[others[i]] = true;
        }
        ghostBalance[deployer] = token.totalSupply();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    // ---------------------------------------------------------------- transfer

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        amount = bound(amount, 0, bal);
        callsTransfer++;

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");

        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
        }
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        excess = bound(excess, 1, type(uint256).max - bal);
        uint256 amount = bal + excess;

        vm.prank(from);
        try token.transfer(to, amount) {
            assertTrue(false, "transfer over balance must revert");
        } catch (bytes memory err) {
            assertEq(
                err,
                abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, from, bal, amount),
                "wrong error for over-balance transfer"
            );
            revertsSeen++;
        }
        assertEq(token.balanceOf(from), bal, "a failed transfer changed the balance");
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        uint256 bal = token.balanceOf(from);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            assertTrue(false, "transfer to the zero address must revert");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
            revertsSeen++;
        }
        assertEq(token.balanceOf(from), bal);
    }

    // ---------------------------------------------------------------- approve

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        callsApprove++;

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            assertTrue(false, "approving the zero spender must revert");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(SqueekToken.InvalidSpender.selector, address(0)));
            revertsSeen++;
        }
        assertEq(token.allowance(owner, address(0)), 0);
    }

    // ---------------------------------------------------------------- transferFrom

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 bal = token.balanceOf(owner);
        uint256 cap = allowed < bal ? allowed : bal;
        amount = bound(amount, 0, cap);
        callsTransferFrom++;

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");

        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        if (owner != to) {
            ghostBalance[owner] -= amount;
            ghostBalance[to] += amount;
            ghostMoved += amount;
        }
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        if (allowed == type(uint256).max) return; // nothing exceeds an unlimited allowance
        excess = bound(excess, 1, type(uint256).max - allowed);
        uint256 amount = allowed + excess;
        uint256 bal = token.balanceOf(owner);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            assertTrue(false, "transferFrom over allowance must revert");
        } catch (bytes memory err) {
            assertEq(
                err,
                abi.encodeWithSelector(SqueekToken.InsufficientAllowance.selector, spender, allowed, amount),
                "wrong error for over-allowance transferFrom"
            );
            revertsSeen++;
        }
        assertEq(token.allowance(owner, spender), allowed, "a failed transferFrom changed the allowance");
        assertEq(token.balanceOf(owner), bal, "a failed transferFrom changed the balance");
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(owner);
        excess = bound(excess, 1, type(uint256).max - 1 - bal);
        uint256 amount = bal + excess;
        uint256 allowed = token.allowance(owner, spender);
        if (allowed != type(uint256).max && allowed < amount) {
            // Give the spender room so the balance check is the one that fires.
            vm.prank(owner);
            token.approve(spender, type(uint256).max - 1);
            ghostAllowance[owner][spender] = type(uint256).max - 1;
            allowed = type(uint256).max - 1;
        }

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            assertTrue(false, "transferFrom over balance must revert");
        } catch (bytes memory err) {
            assertEq(
                err,
                abi.encodeWithSelector(SqueekToken.InsufficientBalance.selector, owner, bal, amount),
                "wrong error for over-balance transferFrom"
            );
            revertsSeen++;
        }
        assertEq(token.allowance(owner, spender), allowed, "a reverted transferFrom must not spend allowance");
        assertEq(token.balanceOf(owner), bal);
    }

    function transferFromToZero(uint256 spenderSeed, uint256 ownerSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        uint256 allowed = token.allowance(owner, spender);
        amount = bound(amount, 0, allowed);
        vm.prank(spender);
        try token.transferFrom(owner, address(0), amount) {
            assertTrue(false, "transferFrom to the zero address must revert");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(SqueekToken.InvalidReceiver.selector, address(0)));
            revertsSeen++;
        }
        assertEq(token.allowance(owner, spender), allowed);
    }

    // ---------------------------------------------------------------- strangers

    /// @dev Somebody outside the actor set can never obtain a balance without an actor sending one,
    /// and cannot take anything from an actor.
    function strangerTries(address stranger, uint256 ownerSeed, uint256 amount) external {
        if (isActor[stranger] || stranger == address(0)) return;
        address owner = _actor(ownerSeed);
        amount = bound(amount, 1, type(uint256).max);
        vm.prank(stranger);
        try token.transferFrom(owner, stranger, amount) {
            assertTrue(false, "a stranger took from an actor");
        } catch {
            revertsSeen++;
        }
        vm.prank(stranger);
        try token.transfer(owner, amount) {
            assertTrue(false, "a stranger sent what it does not hold");
        } catch {
            revertsSeen++;
        }
        assertEq(token.balanceOf(stranger), 0);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    SqueekToken token;
    SqueekHandler handler;
    address deployer = address(0xFAC7);

    function setUp() public {
        vm.prank(deployer);
        token = new SqueekToken();

        address[] memory others = new address[](5);
        others[0] = address(0xA11CE);
        others[1] = address(0xB0B);
        others[2] = address(0xCA201);
        others[3] = address(0xD157); // a distributor-like holder
        others[4] = address(0x9001); // a pool-manager-like holder
        handler = new SqueekHandler(token, deployer, others);
        targetContract(address(handler));
    }

    /// @dev The supply never changes: no call in any order mints or burns.
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// @dev What the actors hold adds up to the whole supply: nothing leaks and nothing appears.
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY, "actor balances do not sum to the supply");
    }

    /// @dev Each balance is exactly what the ghost accounting predicts from successful calls.
    function invariant_balancesMatchGhost() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address a = handler.actors(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "balance drifted from ghost");
        }
    }

    /// @dev Each allowance is exactly what approvals and spends predict; unlimited stays unlimited.
    function invariant_allowancesMatchGhost() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n; j++) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender), "allowance drifted");
            }
        }
    }

    /// @dev No single balance ever exceeds the supply, and the zero address and the token hold nothing.
    function invariant_noBalanceExceedsSupplyAndNoSinkHoldsAnything() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            assertLe(token.balanceOf(handler.actors(i)), SUPPLY);
        }
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    /// @dev Metadata is immutable across any sequence.
    function invariant_metadataIsConstant() public view {
        assertEq(token.name(), "squeek");
        assertEq(token.symbol(), "SQUEEK");
        assertEq(token.decimals(), 18);
    }
}
