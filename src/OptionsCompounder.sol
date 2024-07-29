// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/* Imports */
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IOptionsToken} from "./interfaces/IOptionsToken.sol";
import {DiscountExerciseParams, DiscountExercise} from "./exercise/DiscountExercise.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {OwnableUpgradeable} from "oz-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {ExchangeType, SwapProps, SwapHelper} from "./helpers/SwapHelper.sol";
import "./interfaces/IOptionsCompounder.sol";

/**
 * @title Consumes options tokens, exercise them with flashloaned asset and converts gain to strategy want token
 * @author Eidolon, xRave110
 * @dev Abstract contract which shall be inherited by the strategy
 */
contract OptionsCompounder is IFlashLoanReceiver, OwnableUpgradeable, UUPSUpgradeable, SwapHelper {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    /* Internal struct */
    struct FlashloanParams {
        uint256 optionsAmount;
        address exerciserContract;
        address sender;
        uint256 initialBalance;
        uint256 minPaymentAmount;
    }

    /* Modifier */
    modifier onlyStrat() {
        if (!_isStratAvailable(msg.sender)) {
            revert OptionsCompounder__OnlyStratAllowed();
        }
        _;
    }

    /* Constants */
    uint8 constant MAX_NR_OF_FLASHLOAN_ASSETS = 1;

    uint256 public constant UPGRADE_TIMELOCK = 48 hours;
    uint256 public constant FUTURE_NEXT_PROPOSAL_TIME = 365 days * 100;

    /* Storages */
    ILendingPoolAddressesProvider private addressProvider;
    ILendingPool private lendingPool;
    bool private flashloanFinished;
    IOracle private oracle;
    IOptionsToken public optionsToken;

    uint256 public upgradeProposalTime;
    address public nextImplementation;
    address[] private strats;

    /* Events */
    event OTokenCompounded(uint256 indexed gainInPayment, uint256 indexed returned);

    /* Modifiers */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes params
     * @dev Replaces constructor due to upgradeable nature of the contract. Can be executed only once at init.
     * @param _optionsToken - option token address which allows to redeem underlying token via operation "exercise"
     * @param _addressProvider - address lending pool address provider - necessary for flashloan operations
     * @param _swapProps - swap properites for all swaps in the contract
     * @param _oracle - oracles used in all swaps in the contract
     * @param _strats - list of strategies used to call harvestOTokens()
     *
     */
    function initialize(
        address _optionsToken,
        address _addressProvider,
        SwapProps memory _swapProps,
        IOracle _oracle,
        address[] memory _strats
    ) public initializer {
        __Ownable_init();
        _setOptionsToken(_optionsToken);
        _setSwapProps(_swapProps);
        _setOracle(_oracle);
        _setStrats(_strats);
        flashloanFinished = true;
        _setAddressProvider(_addressProvider);
        __UUPSUpgradeable_init();
        _clearUpgradeCooldown();
    }

    /**
     * Setters **********************************
     */
    /**
     * @notice Sets option token address
     * @dev Can be executed only by admins
     * @param _optionsToken - address of option token contract
     */
    function setOptionsToken(address _optionsToken) external onlyOwner {
        _setOptionsToken(_optionsToken);
    }

    function _setOptionsToken(address _optionsToken) internal {
        if (_optionsToken == address(0)) {
            revert OptionsCompounder__ParamHasAddressZero();
        }
        optionsToken = IOptionsToken(_optionsToken);
    }

    function setSwapProps(SwapProps memory _swapProps) external override onlyOwner {
        _setSwapProps(_swapProps);
    }

    function setOracle(IOracle _oracle) external onlyOwner {
        _setOracle(_oracle);
    }

    function _setOracle(IOracle _oracle) internal {
        if (address(_oracle) == address(0)) {
            revert OptionsCompounder__ParamHasAddressZero();
        }
        oracle = _oracle;
    }

    function setAddressProvider(address _addressProvider) external onlyOwner {
        _setAddressProvider(_addressProvider);
    }

    function _setAddressProvider(address _addressProvider) internal {
        if (_addressProvider == address(0)) {
            revert OptionsCompounder__ParamHasAddressZero();
        }
        addressProvider = ILendingPoolAddressesProvider(_addressProvider);
        lendingPool = ILendingPool(addressProvider.getLendingPool());
    }

    function setStrats(address[] memory _strats) external onlyOwner {
        _setStrats(_strats);
    }

    function _setStrats(address[] memory _strats) internal {
        _deleteStrats();
        for (uint256 idx = 0; idx < _strats.length; idx++) {
            _addStrat(_strats[idx]);
        }
    }

    function addStrat(address _strat) external onlyOwner {
        _addStrat(_strat);
    }

    /**
     * @dev Function will be used sporadically with number of strategies less than 10, so no need to add any gas optimization
     */
    function _addStrat(address _strat) internal {
        if (_strat == address(0)) {
            revert OptionsCompounder__ParamHasAddressZero();
        }
        if (!_isStratAvailable(_strat)) {
            strats.push(_strat);
        }
    }

    function _deleteStrats() internal {
        if (strats.length != 0) {
            delete strats;
        }
    }

    /**
     * @notice Function initiates flashloan to get assets for exercising options.
     * @dev Can be executed only by keeper role. Reentrance protected.
     * @param amount - amount of option tokens to exercise
     * @param exerciseContract - address of exercise contract (DiscountContract)
     * @param minWantAmount - minimal amount of want when the flashloan is considered as profitable
     */
    function harvestOTokens(uint256 amount, address exerciseContract, uint256 minWantAmount) external onlyStrat {
        _harvestOTokens(amount, exerciseContract, minWantAmount);
    }

    /**
     * @notice Function initiates flashloan to get assets for exercising options.
     * @dev Can be executed only by keeper role. Reentrance protected.
     * @param amount - amount of option tokens to exercise
     * @param exerciseContract - address of exercise contract (DiscountContract)
     * @param minPaymentAmount - minimal amount of want when the flashloan is considered as profitable
     */
    function _harvestOTokens(uint256 amount, address exerciseContract, uint256 minPaymentAmount) private {
        /* Check exercise contract validity */
        if (optionsToken.isExerciseContract(exerciseContract) == false) {
            revert OptionsCompounder__NotExerciseContract();
        }
        /* Reentrance protection */
        if (flashloanFinished == false) {
            revert OptionsCompounder__FlashloanNotFinished();
        }
        if (minPaymentAmount == 0) {
            revert OptionsCompounder__WrongMinPaymentAmount();
        }
        /* Locals */
        IERC20 paymentToken = DiscountExercise(exerciseContract).paymentToken();

        address[] memory assets = new address[](1);
        assets[0] = address(paymentToken);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DiscountExercise(exerciseContract).getPaymentAmount(amount);

        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        /* necesary params used during flashloan execution */
        bytes memory params =
            abi.encode(FlashloanParams(amount, exerciseContract, msg.sender, paymentToken.balanceOf(address(this)), minPaymentAmount));
        flashloanFinished = false;
        lendingPool.flashLoan(
            address(this), // receiver
            assets,
            amounts,
            modes,
            address(this), // onBehalf
            params,
            0 // referal code
        );
    }

    /**
     *  @notice Exercise option tokens with flash loaned token and compound rewards
     *  in underlying tokens to stratefy want token
     *  @dev Function is called after this contract has received the flash loaned amount
     *  @param assets - list of assets flash loaned (only one asset allowed in this case)
     *  @param amounts - list of amounts flash loaned (only one amount allowed in this case)
     *  @param premiums - list of premiums for flash loaned assets (only one premium allowed in this case)
     *  @param params - encoded data about options amount, exercise contract address, initial balance and minimal want amount
     *  @return bool - value that returns whether flashloan operation went well
     */
    function executeOperation(address[] calldata assets, uint256[] calldata amounts, uint256[] calldata premiums, address, bytes calldata params)
        external
        override
        returns (bool)
    {
        if (flashloanFinished != false || msg.sender != address(lendingPool)) {
            revert OptionsCompounder__FlashloanNotTriggered();
        }
        if (assets.length > MAX_NR_OF_FLASHLOAN_ASSETS || amounts.length > MAX_NR_OF_FLASHLOAN_ASSETS || premiums.length > MAX_NR_OF_FLASHLOAN_ASSETS)
        {
            revert OptionsCompounder__TooMuchAssetsLoaned();
        }
        /* Later the gain can be local variable */
        _exerciseOptionAndReturnDebt(assets[0], amounts[0], premiums[0], params);
        flashloanFinished = true;
        return true;
    }

    /**
     * @dev Private function that helps to execute flashloan and makes it more modular
     * Emits event with gain from the option exercise after repayment of all debt from flashloan
     * and amount of repaid assets
     *  @param asset - list of assets flash loaned (only one asset allowed in this case)
     *  @param amount - list of amounts flash loaned (only one amount allowed in this case)
     *  @param premium - list of premiums for flash loaned assets (only one premium allowed in this case)
     *  @param params - encoded data about options amount, exercise contract address, initial balance and minimal want amount
     */
    function _exerciseOptionAndReturnDebt(address asset, uint256 amount, uint256 premium, bytes calldata params) private {
        FlashloanParams memory flashloanParams = abi.decode(params, (FlashloanParams));
        uint256 assetBalance = 0;
        uint256 minAmountOut = 0;

        /* Get underlying and payment tokens to make sure there is no change between 
        harvest and excersice */
        IERC20 underlyingToken = DiscountExercise(flashloanParams.exerciserContract).underlyingToken();
        {
            IERC20 paymentToken = DiscountExercise(flashloanParams.exerciserContract).paymentToken();

            /* Asset and paymentToken should be the same addresses */
            if (asset != address(paymentToken)) {
                revert OptionsCompounder__AssetNotEqualToPaymentToken();
            }
        }
        {
            IERC20(address(optionsToken)).safeTransferFrom(flashloanParams.sender, address(this), flashloanParams.optionsAmount);
            bytes memory exerciseParams =
                abi.encode(DiscountExerciseParams({maxPaymentAmount: amount, deadline: block.timestamp, isInstantExit: false}));
            if (underlyingToken.balanceOf(flashloanParams.exerciserContract) < flashloanParams.optionsAmount) {
                revert OptionsCompounder__NotEnoughUnderlyingTokens();
            }
            /* Approve spending payment token */
            IERC20(asset).approve(flashloanParams.exerciserContract, amount);
            /* Exercise in order to get underlying token */
            optionsToken.exercise(flashloanParams.optionsAmount, address(this), flashloanParams.exerciserContract, exerciseParams);

            /* Approve spending payment token to 0 for safety */
            IERC20(asset).approve(flashloanParams.exerciserContract, 0);
        }

        {
            uint256 balanceOfUnderlyingToken = 0;
            uint256 swapAmountOut = 0;
            balanceOfUnderlyingToken = underlyingToken.balanceOf(address(this));
            minAmountOut = _getMinAmountOutData(balanceOfUnderlyingToken, swapProps.maxSwapSlippage, address(oracle));

            /* Approve the underlying token to make swap */
            underlyingToken.approve(swapProps.swapper, balanceOfUnderlyingToken);

            /* Swap underlying token to payment token (asset) */
            swapAmountOut = _generalSwap(
                swapProps.exchangeTypes, address(underlyingToken), asset, balanceOfUnderlyingToken, minAmountOut, swapProps.exchangeAddress
            );

            if (swapAmountOut == 0) {
                revert OptionsCompounder__AmountOutIsZero();
            }

            /* Approve the underlying token to 0 for safety */
            underlyingToken.approve(swapProps.swapper, 0);
        }

        /* Calculate profit and revert if it is not profitable */
        {
            uint256 gainInPaymentToken = 0;

            uint256 totalAmountToPay = amount + premium;
            assetBalance = IERC20(asset).balanceOf(address(this));

            if (
                (
                    (assetBalance < flashloanParams.initialBalance)
                        || (assetBalance - flashloanParams.initialBalance) < (totalAmountToPay + flashloanParams.minPaymentAmount)
                )
            ) {
                revert OptionsCompounder__FlashloanNotProfitableEnough();
            }

            /* Protected against underflows by statement above */
            gainInPaymentToken = assetBalance - totalAmountToPay - flashloanParams.initialBalance;

            /* Approve lending pool to spend borrowed tokens + premium */
            IERC20(asset).approve(address(lendingPool), totalAmountToPay);
            IERC20(asset).safeTransfer(flashloanParams.sender, gainInPaymentToken);

            emit OTokenCompounded(gainInPaymentToken, totalAmountToPay);
        }
    }

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

    /**
     * Getters **********************************
     */
    function isStratAvailable(address strat) external view returns (bool) {
        return _isStratAvailable(strat);
    }

    function _isStratAvailable(address strat) internal view returns (bool) {
        bool isStrat = false;
        address[] memory _strats = strats;
        for (uint256 idx = 0; idx < _strats.length; idx++) {
            if (strat == _strats[idx]) {
                isStrat = true;
                break;
            }
        }
        return isStrat;
    }

    function getStrats() external view returns (address[] memory) {
        return strats;
    }

    function ADDRESSES_PROVIDER() external view returns (ILendingPoolAddressesProvider) {
        return addressProvider;
    }

    function LENDING_POOL() external view returns (ILendingPool) {
        return lendingPool;
    }
}
