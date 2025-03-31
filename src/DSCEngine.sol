//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // for avoiding reentrancy attack
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/*
 * @title DSCEngine
 * @author Elijah Ha
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesAmountDontMatch();
    error DSCEngine_TokenNotAllowed(address token);
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(address user, uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine_Underflow();
    error DSCEngine_WillBreaksHealthFactorAfterRedeem(address user, uint256 healthFactorAfterRedeem);

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private immutable I_DSC;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1 * PRECISION
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need be 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // 50 / 100 = 50%

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeedAddress) private s_priceFeed;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);
    ///////////////////
    // Modifiers
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine_TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    // Funtions
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesAmountDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // Internal & Private Functions
    ///////////////////

    /*
     * Returns how close to liquidation a user is
     * Health Factor = (Collateral Value in USD * Liquidation Threshold) / Minted DSC(Loan Value in USD)
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        // For example:
        // 1500 ETH, 1000 DSC
        // 1500 * 50 / 100 = 750
        // 750 / 1000 = 0.75 < 1
        return (collateralValueInUsd * LIQUIDATION_THRESHOLD * PRECISION / (totalDscMinted * LIQUIDATION_PRECISION)); // avoid consecutive divisions that affect precision
            //return ((((collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health factor (do they have enough collateral value?)
        // 2. Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_BreaksHealthFactor(user, userHealthFactor);
        }
    }

    function _calculateHealthFactorAfterRedeem(address user, address tokenCollateralRedeem, uint256 amountRedeem)
        private
        view
        returns (uint256)
    {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 redeemValueInUsd = getUsdValue(tokenCollateralRedeem, amountRedeem);
        return (
            (collateralValueInUsd - redeemValueInUsd) * LIQUIDATION_THRESHOLD * PRECISION
                / (totalDscMinted * LIQUIDATION_PRECISION)
        );
    }

    ///////////////////
    // Internal & Private View & Pure Functions
    ///////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    ///////////////////
    // External & Public Functions
    ///////////////////

    /**
     * @notice this function will deposit your collateral and mint dsc
     * @param tokenCollateralAddress: The ERC20 token address of collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of dsc you're minting
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI (Checks-Effects-Interactions)
     * @param tokenCollateralAddress: The ERC20 token address of collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_DSC.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    /**
     * @notice follows CEI (Checks-Effects-Interactions)
     * @param tokenCollateralAddress: The ERC20 token address of collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // confirm that the user has sufficient collateral
        if (s_collateralDeposited[msg.sender][tokenCollateralAddress] >= amountCollateral) {
            revert DSCEngine_Underflow();
        }

        // confirm that the user’s health factor isn't less than 1(health) after redeem
        uint256 healthFactorAfterRedeem =
            _calculateHealthFactorAfterRedeem(msg.sender, tokenCollateralAddress, amountCollateral);
        if (healthFactorAfterRedeem < MIN_HEALTH_FACTOR) {
            revert DSCEngine_WillBreaksHealthFactorAfterRedeem(msg.sender, healthFactorAfterRedeem);
        }
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function burnDsc(uint256 amount) external moreThanZero(amount) {
        if (s_DSCMinted[msg.sender] < amount) {
            revert DSCEngine_Underflow();
        }
        s_DSCMinted[msg.sender] -= amount;
        bool success = IERC20(I_DSC).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine_TransferFailed();
        }
        I_DSC.burn(amount);
    }

    ///////////////////
    // External & Public View & Pure Functions
    ///////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited
        // and map it to the price, to get the USD price
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // If 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    ///////////////////
    // Getter Functions
    ///////////////////

    function getPriceFeed(address token) public view returns (address) {
        return s_priceFeed[token];
    }
}
