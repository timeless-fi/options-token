// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IOptionsToken} from "./interfaces/IOptionsToken.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {IExercise} from "./interfaces/IExercise.sol";

/// @title Options Token
/// @author zefram.eth
/// @notice Options token representing the right to perform an advantageous action,
/// such as purchasing the underlying token at a discount to the market price.
contract OptionsToken is IOptionsToken, ERC20, Owned, IERC20Mintable {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error OptionsToken__PastDeadline();
    error OptionsToken__NotTokenAdmin();
    error OptionsToken__NotOption();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Exercise(address indexed sender, address indexed recipient, uint256 amount, bytes parameters);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The contract that has the right to mint options tokens
    address public immutable tokenAdmin;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping (address => bool) public isOption;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address tokenAdmin_
    ) ERC20(name_, symbol_, 18) Owned(owner_) {
        tokenAdmin = tokenAdmin_;
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

    /// @notice Exercises options tokens, giving the reward to the recipient.
    /// @dev WARNING: If `amount` is zero, the bytes returned will be empty and therefore, not decodable.
    /// @dev The options tokens are not burnt but sent to address(0) to avoid messing up the
    /// inflation schedule.
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the reward
    /// @param params Extra parameters to be used by the exercise function
    function exercise(uint256 amount, address recipient, address option, bytes calldata params)
        external
        virtual
        returns (bytes memory)
    {
        return _exercise(amount, recipient, option, params);
    }

    /// @notice Exercises options tokens, giving the reward to the recipient.
    /// @dev WARNING: If `amount` is zero, the bytes returned will be empty and therefore, not decodable.
    /// @dev The options tokens are not burnt but sent to address(0) to avoid messing up the
    /// inflation schedule.
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the reward
    /// @param params Extra parameters to be used by the exercise function
    /// @param deadline The deadline by which the transaction must be mined
    function exercise(uint256 amount, address recipient, address option, bytes calldata params, uint256 deadline)
        external
        virtual
        returns (bytes memory)
    {
        if (block.timestamp > deadline) revert OptionsToken__PastDeadline();
        return _exercise(amount, recipient, option, params);
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Adds a new Exercise contract to the available options.
    /// @param _address Address of the Exercise contract, that implements BaseExercise.
    /// @param _isOption Whether oToken holders should be allowed to exercise using this option.
    function setOption(address _address, bool _isOption) external onlyOwner {
        isOption[_address] = _isOption;
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _exercise(uint256 amount, address recipient, address option, bytes calldata params)
        internal
        virtual
        returns (bytes memory data)
    {
        // skip if amount is zero
        if (amount == 0) return new bytes(0);

        // skip if option is not active
        if (!isOption[option]) revert OptionsToken__NotOption();

        // transfer options tokens from msg.sender to address(0)
        // we transfer instead of burn because TokenAdmin cares about totalSupply
        // which we don't want to change in order to follow the emission schedule
        transfer(address(0), amount);

        // give rewards to recipient
        data = IExercise(option).exercise(msg.sender, amount, recipient, params);

        emit Exercise(msg.sender, recipient, amount, params);
    }
}
