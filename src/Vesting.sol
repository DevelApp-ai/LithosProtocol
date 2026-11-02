// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Vesting
 * @dev Token vesting contract for scheduled distribution of governance tokens
 * Implements cliff periods, linear vesting, and allocation management
 */
contract Vesting is 
    Initializable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant VESTING_ADMIN_ROLE = keccak256("VESTING_ADMIN_ROLE");

    // Vesting schedule structure
    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 vestedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        bool isActive;
        string allocationName;
    }

    // Allocation categories
    enum AllocationType { TEAM, INVESTOR, COMMUNITY, ADVISOR, RESERVE }

    // Storage
    IERC20 public governanceToken;
    mapping(uint256 => VestingSchedule) public vestingSchedules;

    function getVestingSchedule(uint256 scheduleId) external view returns (VestingSchedule memory) {
        return vestingSchedules[scheduleId];
    }
    mapping(address => uint256[]) public beneficiarySchedules;
    
    uint256 public nextScheduleId;
    uint256 public totalAllocated;
    uint256 public totalVested;
    
    // Allocation breakdown (scaled by 100 for percentages)
    mapping(AllocationType => uint256) public allocationPercentages;
    mapping(AllocationType => uint256) public allocationVested;

    // Events
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param _governanceToken Address of the governance token
     */
    function initialize(
        address initialOwner,
        address _governanceToken
    ) initializer public {
        __Ownable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _transferOwnership(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(VESTING_ADMIN_ROLE, initialOwner);

        governanceToken = IERC20(_governanceToken);
        nextScheduleId = 1;

        // Set default allocation percentages
        allocationPercentages[AllocationType.TEAM] = 2000; // 20%
        allocationPercentages[AllocationType.INVESTOR] = 3500; // 35%
        allocationPercentages[AllocationType.COMMUNITY] = 2500; // 25%
        allocationPercentages[AllocationType.ADVISOR] = 1000; // 10%
        allocationPercentages[AllocationType.RESERVE] = 1000; // 10%
    }

    /**
     * @dev Create a new vesting schedule
     * @param beneficiary Address receiving the vested tokens
     * @param amount Total amount to vest
     * @param cliffDuration Duration in seconds before vesting starts
     * @param vestingDuration Total vesting period in seconds
     * @param allocationName Name of the allocation (Team, Investor, etc.)
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        string memory allocationName
    ) public onlyRole(VESTING_ADMIN_ROLE) nonReentrant returns (uint256) {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be positive");
        require(vestingDuration > 0, "Vesting duration must be positive");
        require(cliffDuration <= vestingDuration, "Cliff cannot exceed vesting duration");

        uint256 scheduleId = nextScheduleId++;
        uint256 startTime = block.timestamp + cliffDuration;

        vestingSchedules[scheduleId] = VestingSchedule({
            beneficiary: beneficiary,
            totalAmount: amount,
            vestedAmount: 0,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            isActive: true,
            allocationName: allocationName
        });

        beneficiarySchedules[beneficiary].push(scheduleId);
        totalAllocated += amount;

        emit VestingScheduleCreated(scheduleId, beneficiary, amount, startTime, cliffDuration, vestingDuration, allocationName);

        return scheduleId;
    }

    /**
     * @dev Create multiple vesting schedules for batch allocation
     * @param beneficiaries Array of beneficiary addresses
     * @param amounts Array of amounts to vest
     * @param cliffDuration Duration in seconds before vesting starts
     * @param vestingDuration Total vesting period in seconds
     * @param allocationName Name of the allocation
     */
    function createBatchVestingSchedules(
        address[] memory beneficiaries,
        uint256[] memory amounts,
        uint256 cliffDuration,
        uint256 vestingDuration,
        string memory allocationName
    ) external onlyRole(VESTING_ADMIN_ROLE) {
        require(beneficiaries.length == amounts.length, "Arrays length mismatch");
        require(vestingDuration > 0, "Vesting duration must be positive");
        require(cliffDuration <= vestingDuration, "Cliff cannot exceed vesting duration");

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            createVestingSchedule(
                beneficiaries[i],
                amounts[i],
                cliffDuration,
                vestingDuration,
                allocationName
            );
        }
    }

    /**
     * @dev Claim vested tokens for a specific schedule
     * @param scheduleId The vesting schedule ID
     */
    function claim(uint256 scheduleId) external whenNotPaused nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[scheduleId];
        require(schedule.isActive, "Schedule not active");
        require(msg.sender == schedule.beneficiary, "Not beneficiary");

        uint256 vested = getVestedAmount(scheduleId);
        uint256 claimable = vested - schedule.vestedAmount;

        require(claimable > 0, "No tokens to claim");

        schedule.vestedAmount = vested;

        // Transfer tokens to beneficiary
        require(governanceToken.transfer(schedule.beneficiary, claimable), "Transfer failed");

        totalVested += claimable;
        
        // Update allocation tracking
        AllocationType allocationType = _getAllocationType(schedule.allocationName);
        if (allocationType != AllocationType.RESERVE) {
            allocationVested[allocationType] += claimable;
        }

        emit TokensClaimed(scheduleId, schedule.beneficiary, claimable);

        // Check if fully vested
        if (schedule.vestedAmount >= schedule.totalAmount) {
            schedule.isActive = false;
            emit VestingCompleted(scheduleId, schedule.beneficiary);
        }
    }

    /**
     * @dev Claim all vested tokens across all schedules for caller
     */
    function claimAll() external whenNotPaused nonReentrant {
        uint256[] memory schedules = beneficiarySchedules[msg.sender];
        uint256 totalClaimed = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            uint256 scheduleId = schedules[i];
            VestingSchedule memory schedule = vestingSchedules[scheduleId];
            
            if (schedule.isActive) {
                uint256 vested = getVestedAmount(scheduleId);
                uint256 claimable = vested > schedule.vestedAmount ? 
                    vested - schedule.vestedAmount : 0;

                if (claimable > 0) {
                    vestingSchedules[scheduleId].vestedAmount = vested;
                    require(governanceToken.transfer(msg.sender, claimable), "Transfer failed");
                    totalClaimed += claimable;
                    totalVested += claimable;

                    AllocationType allocationType = _getAllocationType(schedule.allocationName);
                    if (allocationType != AllocationType.RESERVE) {
                        allocationVested[allocationType] += claimable;
                    }

                    emit TokensClaimed(scheduleId, msg.sender, claimable);

                    if (vested >= schedule.totalAmount) {
                        vestingSchedules[scheduleId].isActive = false;
                        emit VestingCompleted(scheduleId, msg.sender);
                    }
                }
            }
        }

        if (totalClaimed > 0) {
            emit TokensClaimed(0, msg.sender, totalClaimed);
        }
    }

    /**
     * @dev Get the current vested amount for a schedule
     * @param scheduleId The vesting schedule ID
     * @return The amount of tokens currently vested
     */
    function getVestedAmount(uint256 scheduleId) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[scheduleId];

        if (!schedule.isActive) {
            return schedule.totalAmount;
        }

        uint256 currentTime = block.timestamp;

        // Before cliff: nothing vested
        if (currentTime < schedule.startTime) {
            return 0;
        }

        // After vesting period: fully vested
        if (currentTime >= schedule.startTime + schedule.vestingDuration) {
            return schedule.totalAmount;
        }

        // Linear vesting between cliff end and vesting end
        uint256 elapsed = currentTime - schedule.startTime;
        uint256 vested = (elapsed * schedule.totalAmount) / schedule.vestingDuration;

        return vested;
    }

    /**
     * @dev Get remaining vesting time for a schedule
     * @param scheduleId The vesting schedule ID
     * @return Remaining seconds until fully vested
     */
    function getRemainingVestingTime(uint256 scheduleId) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[scheduleId];

        if (!schedule.isActive) {
            return 0;
        }

        uint256 vestingEnd = schedule.startTime + schedule.vestingDuration;

        if (block.timestamp >= vestingEnd) {
            return 0;
        }

        return vestingEnd - block.timestamp;
    }

    /**
     * @dev Get all vesting schedules for a beneficiary
     * @param beneficiary The beneficiary address
     * @return Array of schedule IDs
     */
    function getBeneficiarySchedules(address beneficiary) external view returns (uint256[] memory) {
        return beneficiarySchedules[beneficiary];
    }

    /**
     * @dev Get vesting progress for a schedule (0-10000 for percentage)
     * @param scheduleId The vesting schedule ID
     * @return Progress percentage scaled by 10000
     */
    function getVestingProgress(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[scheduleId];
        uint256 vested = getVestedAmount(scheduleId);

        if (schedule.totalAmount == 0) {
            return 10000;
        }

        return (vested * 10000) / schedule.totalAmount;
    }

    /**
     * @dev Fund the vesting contract with tokens for distribution
     * @param amount Amount of tokens to deposit
     */
    function fund(uint256 amount) external onlyRole(VESTING_ADMIN_ROLE) nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(governanceToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    /**
     * @dev Get contract token balance
     * @return Current token balance
     */
    function getContractBalance() external view returns (uint256) {
        return governanceToken.balanceOf(address(this));
    }

    /**
     * @dev Update allocation percentages
     * @param allocationType The allocation category
     * @param percentage New percentage (scaled by 100)
     */
    function updateAllocationPercentage(
        AllocationType allocationType,
        uint256 percentage
    ) external onlyRole(VESTING_ADMIN_ROLE) {
        allocationPercentages[allocationType] = percentage;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /**
     * @dev Internal function to get allocation type from name
     */
    function _getAllocationType(string memory name) internal pure returns (AllocationType) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        bytes32 teamHash = keccak256(abi.encodePacked("Team"));
        bytes32 investorHash = keccak256(abi.encodePacked("Investor"));
        bytes32 communityHash = keccak256(abi.encodePacked("Community"));
        bytes32 advisorHash = keccak256(abi.encodePacked("Advisor"));

        if (nameHash == teamHash) return AllocationType.TEAM;
        if (nameHash == investorHash) return AllocationType.INVESTOR;
        if (nameHash == communityHash) return AllocationType.COMMUNITY;
        if (nameHash == advisorHash) return AllocationType.ADVISOR;

        return AllocationType.RESERVE;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
