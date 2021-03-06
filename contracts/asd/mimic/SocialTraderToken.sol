// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./TraderManager.sol";
import "../ERC677/ERC677.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract SocialTraderToken is ERC677 {
    using SafeMath for uint256;
    /**
     * @dev Struct that represents the allowed moves for a follower
     */
    struct AllowedMoves {
        TraderManager.OptionStyle[2] styles;
        TraderManager.TradingType[] types;
    }
    /**
     * @dev Struct that represents the token obligations for the follower
     */
    struct TokenObligation {
        address[] tokensObligated;
        mapping(address => uint256) tokensInitialAmount;
        mapping(address => uint256) tokensObligatedAmount;
    }
    /**
     * @dev Address of the trader manager contract
     */
     address public TRADER_MANAGER;
    /**
     * @dev Address of the token for fees
     */
    address public FEE_TOKEN_ADDRESS;
    /**
     * @dev Fee for minting tokens
     * FEE_PER_TOKEN represents 1.00... token
     * FEE = FEE_PER_TOKEN * # of tokens
     */
    uint256 public FEE_PER_TOKEN;
    /**
     * @dev Fee for profit taking
     * Precision of 100.xx (100.00% - 0.00%)
     */
    uint16 public PROFIT_TAKE_FEE;
    /**
     * @dev Minimum amount to mint new Social Trader tokens
     */
    uint256 public MINIMUM_MINT;
    /**
     * @dev Address of the social trader associated with this token
     */
    address immutable public socialTrader;
    /**
     * @dev Allow to mint new tokens
     */
    bool public allowNewMints = true;
    /**
     * @dev Tokens used for committing trades
     */
    address[] public tokensPooled;
    /**
     * @dev Permissions of a follower's moves
     */
    mapping(address => AllowedMoves) private followerPermissions;
    /**
     * @dev Mapping of each pooled token that represents a ratio of what can be redeemed
     */
    mapping(address => uint256) private poolTokenRatio;
    /**
     * @dev Mapping of each participant that represents what pool tokens they're obligated to
     */
    mapping(address => TokenObligation) private poolTokenObligation;

    event TraderManagerChanged(address _newTraderManager);
    event MintsAvailable();
    event MintsUnavailable();

    constructor(
        string memory _name, 
        string memory _symbol,
        address _TRADER_MANAGER,
        address _FEE_TOKEN_ADDRESS,
        uint256 _FEE_PER_TOKEN,
        uint16 _PROFIT_TAKE_FEE,
        uint256 _MINIMUM_MINT,
        address _socialTrader
    ) 
        ERC677(_name, _symbol) 
    {
        require(
            _socialTrader != address(0)
        );
        if(_FEE_PER_TOKEN > 0) {
            require(
                _FEE_TOKEN_ADDRESS != address(0)
            );
        }
        TRADER_MANAGER = _TRADER_MANAGER;
        FEE_TOKEN_ADDRESS = _FEE_TOKEN_ADDRESS;
        FEE_PER_TOKEN = _FEE_PER_TOKEN;
        PROFIT_TAKE_FEE = _PROFIT_TAKE_FEE;
        MINIMUM_MINT = _MINIMUM_MINT;
        socialTrader = _socialTrader;
    }

    modifier onlySocialTrader {
        _onlySocialTrader();
        _;
    }
    modifier onlyFollower {
        _onlyFollower();
        _;
    }

    function burnTokens(uint256 _amount) public {
        _burn(msg.sender, _amount);
        // Redeem collateral/underlying and profits if any
    }
    function mintTokens(uint256 _amount) public {
        require(
            allowNewMints,
            "Mints not allowed"
        );
        require(
            _amount >= MINIMUM_MINT
        );
        _chargeFee(_amount);
        _mint(msg.sender, _amount);
    }
    function redeemProfits(address[] memory _tokens) public onlyFollower {
        for(uint256 i; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            uint256 tokenInitialAmt = poolTokenObligation[msg.sender].tokensInitialAmount[_tokens[i]];
            uint256 tokenObligatedAmt = poolTokenObligation[msg.sender].tokensObligatedAmount[_tokens[i]];
            if(tokenInitialAmt < tokenObligatedAmt) {
                token.transfer(msg.sender, tokenObligatedAmt-tokenInitialAmt);
                poolTokenObligation[msg.sender].tokensObligatedAmount[_tokens[i]] = tokenInitialAmt;
            }
        }
    }
    function redeemFees() public onlySocialTrader {
        IERC20 token = IERC20(FEE_TOKEN_ADDRESS);
        token.transfer(
            socialTrader, 
            token.balanceOf(address(this))
        );
    }
    function changeFeeToken(address _token) public onlySocialTrader {
        FEE_TOKEN_ADDRESS = _token;
    }
    function changeFee(uint256 _amount) public onlySocialTrader {
        if(_amount > 0) {
            require(
                FEE_TOKEN_ADDRESS != address(0)
            );
        }
        FEE_PER_TOKEN = _amount;
    }
    function changeProfitTakeFee(uint16 _percentage) public onlySocialTrader {
        require(
            _percentage <= 10000
        );
        PROFIT_TAKE_FEE = _percentage;
    }
    function openPosition(
        TraderManager.OptionStyle _style,
        TraderManager.TradingType _type,
        address _oTokenAddress
    ) 
        public 
        onlySocialTrader
        returns(uint256 _positionIndex) 
    {
        // Filter addresses 
    }
    function closePosition(
        uint256 _positionIndex
    )
        public
        onlySocialTrader
    {

    }
    function isFollower(address _account) public view returns(bool) {
        return balanceOf(_account) > 0;
    }
    function filterEligibleAddresses(
        TraderManager.OptionStyle _style,
        TraderManager.TradingType _type,
        address[] memory addresses
    ) 
        public 
        view 
        returns(address[] memory filtered) 
    {
        filtered = addresses;

        for(uint256 i = 0; i < addresses.length; i++) {
            bool styleAllowed;
            bool typeAllowed;
            // Check if the style is allowed
            for(uint256 j = 0; j < followerPermissions[addresses[i]].styles.length; j++) {
                if(followerPermissions[addresses[i]].styles[j] == _style) {
                    styleAllowed = true;
                    break;
                }
            }
            // Check if the type is allowed
            for(uint256 j = 0; j < followerPermissions[addresses[i]].types.length; j++) {
                if(followerPermissions[addresses[i]].types[j] == _type) {
                    typeAllowed = true;
                    break;
                }
            }
            if(!styleAllowed || !typeAllowed) {
                delete filtered[i];
            }
        }

        return filtered;
    }
    function _onlySocialTrader() internal view {
        require(
            msg.sender == socialTrader,
            "Not authorized"
        );
    }
    function _onlyFollower() internal view {
        require(
            balanceOf(msg.sender) > 0,
            "Not a follower"
        );
    }
    function _chargeFee(uint256 _minted) internal {
        transferFrom(
            msg.sender, address(this), 
            _minted.mul(FEE_PER_TOKEN)
        );
    }
    function _recalculateTokenObligation() internal {

    }
    function _redeemFunds() internal {
        // Redeems underlying/collateral + profits (if any)
    }

}
