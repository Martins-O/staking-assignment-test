// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import  "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/StakingRewards.sol";
import {MockERC20} from "src/MockERC20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function  test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");

    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether)/uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Test when current time is before finish time
        uint256 currentTime = block.timestamp;
        assertEq(staking.lastTimeRewardApplicable(), currentTime);

        // Test when current time is after finish time
        vm.warp(block.timestamp + 2 weeks);
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt());
    }

    function test_rewardPerToken() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Test when total supply is 0
        assertEq(staking.rewardPerToken(), 0);

        // Add some stake to make totalSupply > 0
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);
        vm.stopPrank();

        // Move time forward and check reward per token
        vm.warp(block.timestamp + 1 days);
        uint256 rewardPerToken = staking.rewardPerToken();
        assertGt(rewardPerToken, 0);
    }

    function test_earned() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Initial earned should be 0
        assertEq(staking.earned(bob), 0);

        // Stake some tokens
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);
        vm.stopPrank();

        // Move time forward
        vm.warp(block.timestamp + 1 days);

        // Check earned rewards
        uint256 earned = staking.earned(bob);
        assertGt(earned, 0);
    }

    function test_getReward() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Stake some tokens
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);

        // Move time forward to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Check initial state
        uint256 earnedBefore = staking.earned(bob);
        assertGt(earnedBefore, 0);

        uint256 rewardTokenBalanceBefore = IERC20(address(rewardToken)).balanceOf(bob);

        // Get reward
        staking.getReward();

        // Check rewards were transferred
        uint256 rewardTokenBalanceAfter = IERC20(address(rewardToken)).balanceOf(bob);
        assertGt(rewardTokenBalanceAfter, rewardTokenBalanceBefore);

        // Check rewards mapping was reset
        assertEq(staking.rewards(bob), 0);
        vm.stopPrank();
    }

    function test_getReward_noRewards() public {
        // Test getReward when user has no rewards
        vm.prank(bob);
        staking.getReward(); // Should not revert and should do nothing

        assertEq(staking.rewards(bob), 0);
        assertEq(IERC20(address(rewardToken)).balanceOf(bob), 0);
    }

    function test_notifyRewardAmount_beforeFinish() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(rewardToken), owner, 200 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 200 ether);

        // First notification
        staking.notifyRewardAmount(100 ether);
        uint256 firstRewardRate = staking.rewardRate();
        uint256 firstFinishAt = staking.finishAt();

        // Move time forward but not past finish
        vm.warp(block.timestamp + 2 days);

        // Second notification while first period is still active
        staking.notifyRewardAmount(50 ether);

        // Should have different reward rate that accounts for remaining rewards
        uint256 secondRewardRate = staking.rewardRate();
        assertGt(secondRewardRate, firstRewardRate);

        // Should have new finish time
        uint256 secondFinishAt = staking.finishAt();
        assertGt(secondFinishAt, firstFinishAt);

        vm.stopPrank();
    }


}
