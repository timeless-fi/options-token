// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "oz-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "oz-upgradeable/security/PausableUpgradeable.sol";
import {IOptionsToken} from "./interfaces/IOptionsToken.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IExercise} from "./interfaces/IExercise.sol";

/// @title Options Token
/// @author Eidolon & lookee
/// @notice Options token representing the right to perform an advantageous action,
/// such as purchasing the underlying token at a discount to the market price.
contract OptionsToken is IOptionsToken, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error OptionsToken__NotTokenAdmin();
    error OptionsToken__NotExerciseContract();
    error Upgradeable__Unauthorized();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Exercise(address indexed sender, address indexed recipient, uint256 amount, address data0, uint256 data1, uint256 data2);
    event SetOracle(IOracle indexed newOracle);
    event SetExerciseContract(address indexed _address, bool _isExercise);

    /// -----------------------------------------------------------------------
    /// Constant parameters
    /// -----------------------------------------------------------------------

    uint256 public constant UPGRADE_TIMELOCK = 48 hours;
    uint256 public constant FUTURE_NEXT_PROPOSAL_TIME = 365 days * 100;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The contract that has the right to mint options tokens
    address public tokenAdmin;

    mapping(address => bool) public isExerciseContract;
    uint256 public upgradeProposalTime;
    address public nextImplementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// -----------------------------------------------------------------------
    /// Initializer
    /// -----------------------------------------------------------------------

    function initialize(string memory name_, string memory symbol_, address tokenAdmin_) external initializer {
        __UUPSUpgradeable_init();
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        __Pausable_init();
        tokenAdmin = tokenAdmin_;

        _clearUpgradeCooldown();
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Called by the token admin to mint options tokens
    /// @param to The address that will receive the minted options tokens
    /// @param amount The amount of options tokens that will be minted
    function mint(address to, uint256 amount) external virtual override {
        /// -----------------------------------------------------------------------
        /// Verification
        /// -----------------------------------------------------------------------

        if (msg.sender != tokenAdmin) revert OptionsToken__NotTokenAdmin();

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // skip if amount is zero
        if (amount == 0) return;

        // mint options tokens
        _mint(to, amount);
    }

    /// @notice Exercises options tokens, burning them and giving the reward to the recipient.
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the reward
    /// @param option The address of the Exercise contract with the redemption logic
    /// @param params Extra parameters to be used by the exercise function
    /// @return paymentAmount token amount paid for exercising
    /// @return data0 address data to return by different exerciser contracts
    /// @return data1 integer data to return by different exerciser contracts
    /// @return data2 additional integer data to return by different exerciser contracts
    function exercise(uint256 amount, address recipient, address option, bytes calldata params)
        external
        virtual
        whenNotPaused
        returns (
            uint256 paymentAmount,
            address,
            uint256,
            uint256 // misc data
        )
    {
        return _exercise(amount, recipient, option, params);
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Adds a new Exercise contract to the available options.
    /// @param _address Address of the Exercise contract, that implements BaseExercise.
    /// @param _isExercise Whether oToken holders should be allowed to exercise using this option.
    function setExerciseContract(address _address, bool _isExercise) external onlyOwner {
        isExerciseContract[_address] = _isExercise;
        emit SetExerciseContract(_address, _isExercise);
    }

    /// @notice Pauses functionality related to exercises of contracts.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses functionality related to exercises of contracts.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _exercise(uint256 amount, address recipient, address option, bytes calldata params)
        internal
        virtual
        returns (
            uint256 paymentAmount,
            address data0,
            uint256 data1,
            uint256 data2 // misc data
        )
    {
        // skip if amount is zero
        if (amount == 0) return (0, address(0), 0, 0);

        // revert if the exercise contract is not whitelisted
        if (!isExerciseContract[option]) revert OptionsToken__NotExerciseContract();

        // burn options tokens
        _burn(msg.sender, amount);

        // give rewards to recipient
        (paymentAmount, data0, data1, data2) = IExercise(option).exercise(msg.sender, amount, recipient, params);

        // emit event
        emit Exercise(msg.sender, recipient, amount, data0, data1, data2);
    }

    /// -----------------------------------------------------------------------
    /// UUPS functions
    /// -----------------------------------------------------------------------

    /**
     * @dev This function must be called prior to upgrading the implementation.
     *      It's required to wait UPGRADE_TIMELOCK seconds before executing the upgrade.
     */
    function initiateUpgradeCooldown(address _nextImplementation) external onlyOwner {
        upgradeProposalTime = block.timestamp;
        nextImplementation = _nextImplementation;
    }

    /**
     * @dev This function is called:
     *      - in initialize()
     *      - as part of a successful upgrade
     *      - manually to clear the upgrade cooldown.
     */
    function _clearUpgradeCooldown() internal {
        upgradeProposalTime = block.timestamp + FUTURE_NEXT_PROPOSAL_TIME;
    }

    function clearUpgradeCooldown() external onlyOwner {
        _clearUpgradeCooldown();
    }

    /**
     * @dev This function must be overriden simply for access control purposes.
     *      Only the owner can upgrade the implementation once the timelock
     *      has passed.
     */
    function _authorizeUpgrade(address _nextImplementation) internal override onlyOwner {
        require(upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp, "Upgrade cooldown not initiated or still ongoing");
        require(_nextImplementation == nextImplementation, "Incorrect implementation");
        _clearUpgradeCooldown();
    }
}
