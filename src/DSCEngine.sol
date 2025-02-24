//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // for avoiding reentrancy attack
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    error DSCEngine_TransferFailed(address from, address to, address token, uint256 value);

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private immutable i_dsc;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeedAddress) private s_priceFeed;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    ///////////////////
    // Events
    ///////////////////
    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    /**
     * @notice follows CEI (Checks-Effects-Interactions)
     * @param tokenCollateralAddress: The ERC20 token address of collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit collateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferFailed(msg.sender, address(this), tokenCollateralAddress, amountCollateral);
        }
    }

    function redeemCollateral() external {}
}
