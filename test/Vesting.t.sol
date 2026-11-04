// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Vesting.sol";
import "../src/GovernanceToken.sol";

contract VestingTest is Test {
    Vesting public vesting;
    GovernanceToken public governanceToken;
    
    address public owner = address(0x1);
    address public beneficiary1 = address(0x2);
    address public beneficiary2 = address(0x3);
    address public vestingAdmin = address(0x4);
    
    event VestingScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        string allocationName
    );
    event TokensVested(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event TokensClaimed(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event VestingCompleted(uint256 indexed scheduleId, address indexed beneficiary);
    
    function setUp() public {
        // Deploy governance token
        GovernanceToken govImpl = new GovernanceToken();
        bytes memory govInitData = abi.encodeWithSelector(
            GovernanceToken.initialize.selector,
            owner,
            "Aetherium Governance",
            "GOV",
            1000000 * 10**18
        );
        ERC1967Proxy govProxy = new ERC1967Proxy(address(govImpl), govInitData);
        governanceToken = GovernanceToken(address(govProxy));
        
        // Deploy vesting contract
        Vesting vestingImpl = new Vesting();
        bytes memory vestingInitData = abi.encodeWithSelector(
            Vesting.initialize.selector,
            owner,
            address(governanceToken)
        );
        ERC1967Proxy vestingProxy = new ERC1967Proxy(address(vestingImpl), vestingInitData);
        vesting = Vesting(address(vestingProxy));
        
        // Setup permissions
        vm.startPrank(owner);
        governanceToken.transfer(address(vesting), 500000 * 10**18); // Fund vesting contract
        vesting.grantRole(vesting.VESTING_ADMIN_ROLE(), vestingAdmin);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(address(vesting.governanceToken()), address(governanceToken));
        assertEq(vesting.owner(), owner);
        assertEq(vesting.nextScheduleId(), 1);
        assertEq(vesting.totalAllocated(), 0);
        assertEq(vesting.totalVested(), 0);
    }
    
    function testCreateVestingSchedule() public {
        vm.startPrank(vestingAdmin);
        
        vm.expectEmit(true, true, true, false);
        emit VestingScheduleCreated(1, beneficiary1, 1000 * 10**18, 0, 0, 365 days, "Team");
        
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0, // No cliff
            365 days,
            "Team"
        );
        
        assertEq(scheduleId, 1);
        
        Vesting.VestingSchedule memory schedule = vesting.getVestingSchedule(scheduleId);
        assertEq(schedule.beneficiary, beneficiary1);
        assertEq(schedule.totalAmount, 1000 * 10**18);
        assertEq(schedule.vestedAmount, 0);
        assertEq(schedule.vestingDuration, 365 days);
        assertTrue(schedule.isActive);
        
        // Check allocation tracking
        assertEq(vesting.totalAllocated(), 1000 * 10**18);
        
        // Check beneficiary schedules
        uint256[] memory schedules = vesting.getBeneficiarySchedules(beneficiary1);
        assertEq(schedules.length, 1);
        assertEq(schedules[0], scheduleId);
        
        vm.stopPrank();
    }
    
    function testCreateVestingScheduleWithCliff() public {
        vm.startPrank(vestingAdmin);
        
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            90 days, // 3 month cliff
            365 days,
            "Investor"
        );
        
        assertEq(scheduleId, 1); // nextScheduleId starts at 1
        
        Vesting.VestingSchedule memory schedule = vesting.getVestingSchedule(scheduleId);
        assertEq(schedule.cliffDuration, 90 days);
        assertEq(schedule.startTime, block.timestamp + 90 days);
        
        vm.stopPrank();
    }
    
    function testCreateBatchVestingSchedules() public {
        address[] memory beneficiaries = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        amounts[0] = 500 * 10**18;
        amounts[1] = 300 * 10**18;
        
        vm.startPrank(vestingAdmin);
        vesting.createBatchVestingSchedules(
            beneficiaries,
            amounts,
            0,
            365 days,
            "Community"
        );
        vm.stopPrank();
        
        // Check both schedules created
        assertEq(vesting.nextScheduleId(), 3); // starts at 1, batch adds 2
        assertEq(vesting.totalAllocated(), 800 * 10**18); // 500 + 300
        
        uint256[] memory schedules1 = vesting.getBeneficiarySchedules(beneficiary1);
        uint256[] memory schedules2 = vesting.getBeneficiarySchedules(beneficiary2);
        
        assertEq(schedules1.length, 1);
        assertEq(schedules2.length, 1);
    }
    
    function testGetVestedAmountBeforeCliff() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            90 days,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Before cliff, should be 0
        assertEq(vesting.getVestedAmount(scheduleId), 0);
    }
    
    function testGetVestedAmountDuringVesting() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0, // No cliff
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Fast forward 180 days (half the vesting period)
        vm.warp(block.timestamp + 180 days);
        
        // Linear vesting over 365 days from creation: 180/365 ~= 49.3%
        uint256 vested = vesting.getVestedAmount(scheduleId);
        assertGt(vested, 493 * 10**18); // 180/365 of 1000 tokens
        assertLt(vested, 494 * 10**18);
    }
    
    function testGetVestedAmountAfterVesting() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Fast forward past vesting period
        vm.warp(block.timestamp + 366 days);
        
        // Should be fully vested
        assertEq(vesting.getVestedAmount(scheduleId), 1000 * 10**18);
    }
    
    function testClaimVestedTokens() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Fast forward to vest some tokens
        vm.warp(block.timestamp + 180 days);
        
        uint256 vestedBefore = vesting.getVestedAmount(scheduleId);
        uint256 balanceBefore = governanceToken.balanceOf(beneficiary1);
        
        // Claim vested tokens
        vm.startPrank(beneficiary1);
        
        vm.expectEmit(true, true, true, false);
        emit TokensClaimed(scheduleId, beneficiary1, vestedBefore);
        
        vesting.claim(scheduleId);
        
        vm.stopPrank();
        
        // Check tokens transferred
        assertEq(governanceToken.balanceOf(beneficiary1), balanceBefore + vestedBefore);
        
        // Check schedule updated
        Vesting.VestingSchedule memory schedule = vesting.getVestingSchedule(scheduleId);
        assertEq(schedule.vestedAmount, vestedBefore);
        
        // Check total vested updated
        assertEq(vesting.totalVested(), vestedBefore);
    }
    
    function testClaimAll() public {
        vm.startPrank(vestingAdmin);
        // Create multiple schedules for same beneficiary
        vesting.createVestingSchedule(
            beneficiary1,
            500 * 10**18,
            0,
            365 days,
            "Team"
        );
        vesting.createVestingSchedule(
            beneficiary1,
            300 * 10**18,
            0,
            180 days,
            "Advisor"
        );
        vm.stopPrank();
        
        // Fast forward to vest some tokens
        vm.warp(block.timestamp + 90 days);
        
        uint256 balanceBefore = governanceToken.balanceOf(beneficiary1);
        
        // Claim all vested tokens
        vm.startPrank(beneficiary1);
        vesting.claimAll();
        vm.stopPrank();
        
        // Should have received vested tokens from both schedules
        assertGt(governanceToken.balanceOf(beneficiary1), balanceBefore);
    }
    
    function testCannotClaimBeforeVesting() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Try to claim before any vesting
        vm.startPrank(beneficiary1);
        vm.expectRevert("No tokens to claim");
        vesting.claim(scheduleId);
        vm.stopPrank();
    }
    
    function testCannotClaimForOthers() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // Fast forward to vest some tokens
        vm.warp(block.timestamp + 180 days);
        
        // Try to claim as non-beneficiary
        vm.startPrank(beneficiary2);
        vm.expectRevert("Not beneficiary");
        vesting.claim(scheduleId);
        vm.stopPrank();
    }
    
    function testGetVestingProgress() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        // At start, 0% progress
        assertEq(vesting.getVestingProgress(scheduleId), 0);
        
        // After 180 days, ~50% progress
        vm.warp(block.timestamp + 180 days);
        uint256 progress = vesting.getVestingProgress(scheduleId);
        assertGt(progress, 4930); // 180/365 ~= 49.3% -> ~4931 bps
        assertLt(progress, 4932);
        
        // After full vesting, 100% progress
        vm.warp(block.timestamp + 366 days);
        assertEq(vesting.getVestingProgress(scheduleId), 10000);
    }
    
    function testGetRemainingVestingTime() public {
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        
        uint256 initialTime = block.timestamp;
        
        // Initially, should be full vesting duration
        assertEq(vesting.getRemainingVestingTime(scheduleId), 365 days);
        
        // After 100 days
        vm.warp(initialTime + 100 days);
        assertEq(vesting.getRemainingVestingTime(scheduleId), 265 days);
        
        // After vesting period
        vm.warp(initialTime + 366 days);
        assertEq(vesting.getRemainingVestingTime(scheduleId), 0);
    }
    
    function testFundVestingContract() public {
        uint256 initialBalance = governanceToken.balanceOf(address(vesting));
        
        vm.startPrank(owner);
        governanceToken.approve(address(vesting), 1000 * 10**18);
        vesting.fund(1000 * 10**18);
        vm.stopPrank();
        
        assertEq(governanceToken.balanceOf(address(vesting)), initialBalance + 1000 * 10**18);
    }
    
    function testGetContractBalance() public {
        assertEq(vesting.getContractBalance(), governanceToken.balanceOf(address(vesting)));
    }
    
    function testUpdateAllocationPercentage() public {
        vm.startPrank(owner);
        vesting.updateAllocationPercentage(Vesting.AllocationType.TEAM, 2500); // 25%
        assertEq(vesting.allocationPercentages(Vesting.AllocationType.TEAM), 2500);
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        vesting.pause();
        assertTrue(vesting.paused());
        
        vm.stopPrank();
        
        // Try to claim while paused (claims are gated by whenNotPaused)
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
        vm.startPrank(beneficiary1);
        vm.expectRevert("Pausable: paused");
        vesting.claim(scheduleId);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        vesting.unpause();
        assertFalse(vesting.paused());
        vm.stopPrank();
    }
    
    function testCannotCreateScheduleWithZeroAmount() public {
        vm.startPrank(vestingAdmin);
        vm.expectRevert("Amount must be positive");
        vesting.createVestingSchedule(
            beneficiary1,
            0,
            0,
            365 days,
            "Team"
        );
        vm.stopPrank();
    }
    
    function testCannotCreateScheduleWithZeroDuration() public {
        vm.startPrank(vestingAdmin);
        vm.expectRevert("Vesting duration must be positive");
        vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            0,
            0,
            "Team"
        );
        vm.stopPrank();
    }
    
    function testCliffCannotExceedVestingDuration() public {
        vm.startPrank(vestingAdmin);
        vm.expectRevert("Cliff cannot exceed vesting duration");
        vesting.createVestingSchedule(
            beneficiary1,
            1000 * 10**18,
            400 days, // Cliff longer than vesting
            365 days,
            "Team"
        );
        vm.stopPrank();
    }
    
    function testFuzzVestingSchedule(uint256 amount, uint256 cliff, uint256 duration) public {
        vm.assume(amount > 0);
        vm.assume(duration > 0);
        vm.assume(cliff <= duration);
        
        vm.startPrank(vestingAdmin);
        uint256 scheduleId = vesting.createVestingSchedule(
            beneficiary1,
            amount,
            cliff,
            duration,
            "Test"
        );
        vm.stopPrank();
        
        Vesting.VestingSchedule memory _schedule = vesting.getVestingSchedule(scheduleId);
        assertEq(_schedule.totalAmount, amount);
        assertEq(_schedule.vestingDuration, duration);
    }
}
