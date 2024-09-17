/*
LAW OF ATTRACTION 
*/


// SPDX-License-Identifier: No License
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable2Step.sol";
import "./Initializable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router01.sol";
import "./IUniswapV2Router02.sol";

contract Law_of__Attraction is ERC20, ERC20Burnable, Ownable2Step, Initializable {
    
    uint16 public swapThresholdRatio;
    
    uint256 private _walletPending;
    uint256 private _liquidityPending;

    address public walletAddress;
    uint16[3] public walletFees;

    uint16[3] public liquidityFees;

    mapping (address => bool) public isExcludedFromFees;

    uint16[3] public totalFees;
    bool private _swapping;

    IUniswapV2Router02 public routerV2;
    address public pairV2;
    mapping (address => bool) public AMMPairs;

    bool public tradingEnabled;
    mapping (address => bool) public isExcludedFromTradingRestriction;
 
    event SwapThresholdUpdated(uint16 swapThresholdRatio);

    event walletAddressUpdated(address walletAddress);
    event walletFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event walletFeeSent(address recipient, uint256 amount);

    event liquidityFeesUpdated(uint16 buyFee, uint16 sellFee, uint16 transferFee);
    event liquidityAdded(uint amountToken, uint amountCoin, uint liquidity);
    event ForceLiquidityAdded(uint256 leftoverTokens, uint256 unaddedTokens);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event RouterV2Updated(address indexed routerV2);
    event AMMPairsUpdated(address indexed AMMPair, bool isPair);

    event TradingEnabled();
    event ExcludeFromTradingRestriction(address indexed account, bool isExcluded);
 
    constructor()
        ERC20(unicode"Law of  Attraction", unicode"LOA") 
    {
        address supplyRecipient = 0xBDf97C3D4893846770b39166E74B26280d69b0c0;
        
        updateSwapThreshold(50);

        walletAddressSetup(0x68dd40d67765B2D66b50dF27a641fCFd497Cc6C8);
        walletFeesSetup(30, 59, 0);

        liquidityFeesSetup(50, 40, 0);

        excludeFromFees(supplyRecipient, true);
        excludeFromFees(address(this), true); 

        excludeFromTradingRestriction(supplyRecipient, true);
        excludeFromTradingRestriction(address(this), true);

        _mint(supplyRecipient, 1000000000 * (10 ** decimals()) / 10);
        _transferOwnership(0xBDf97C3D4893846770b39166E74B26280d69b0c0);
    }
    
    /*
        This token is not upgradeable, but uses both the constructor and initializer for post-deployment setup.
    */
    function initialize(address _router) initializer external {
        _updateRouterV2(_router);
    }

    receive() external payable {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    function _swapTokensForCoin(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerV2.WETH();

        _approve(address(this), address(routerV2), tokenAmount);

        routerV2.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function updateSwapThreshold(uint16 _swapThresholdRatio) public onlyOwner {
        require(_swapThresholdRatio > 0 && _swapThresholdRatio <= 500, "SwapThreshold: Cannot exceed limits from 0.01% to 5% for new swap threshold");
        swapThresholdRatio = _swapThresholdRatio;
        
        emit SwapThresholdUpdated(_swapThresholdRatio);
    }

    function getSwapThresholdAmount() public view returns (uint256) {
        return balanceOf(pairV2) * swapThresholdRatio / 10000;
    }

    function getAllPending() public view returns (uint256) {
        return 0 + _walletPending + _liquidityPending;
    }

    function walletAddressSetup(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "TaxesDefaultRouterWallet: Wallet tax recipient cannot be a 0x0 address");

        walletAddress = _newAddress;
        excludeFromFees(_newAddress, true);

        emit walletAddressUpdated(_newAddress);
    }

    function walletFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - walletFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - walletFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - walletFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        walletFees = [_buyFee, _sellFee, _transferFee];

        emit walletFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function _swapAndLiquify(uint256 tokenAmount) private returns (uint256 leftover) {
        // Sub-optimal method for supplying liquidity
        uint256 halfAmount = tokenAmount / 2;
        uint256 otherHalf = tokenAmount - halfAmount;

        _swapTokensForCoin(halfAmount);

        uint256 coinBalance = address(this).balance;

        if (coinBalance > 0) {
            (uint amountToken, uint amountCoin, uint liquidity) = _addLiquidity(otherHalf, coinBalance);

            emit liquidityAdded(amountToken, amountCoin, liquidity);

            return otherHalf - amountToken;
        } else {
            return otherHalf;
        }
    }

    function _addLiquidity(uint256 tokenAmount, uint256 coinAmount) private returns (uint, uint, uint) {
        _approve(address(this), address(routerV2), tokenAmount);

        return routerV2.addLiquidityETH{value: coinAmount}(address(this), tokenAmount, 0, 0, address(0), block.timestamp);
    }

    function addLiquidityFromLeftoverTokens() external {
        uint256 leftoverTokens = balanceOf(address(this)) - getAllPending();

        uint256 unaddedTokens = _swapAndLiquify(leftoverTokens);

        emit ForceLiquidityAdded(leftoverTokens, unaddedTokens);
    }

    function liquidityFeesSetup(uint16 _buyFee, uint16 _sellFee, uint16 _transferFee) public onlyOwner {
        totalFees[0] = totalFees[0] - liquidityFees[0] + _buyFee;
        totalFees[1] = totalFees[1] - liquidityFees[1] + _sellFee;
        totalFees[2] = totalFees[2] - liquidityFees[2] + _transferFee;
        require(totalFees[0] <= 2500 && totalFees[1] <= 2500 && totalFees[2] <= 2500, "TaxesDefaultRouter: Cannot exceed max total fee of 25%");

        liquidityFees = [_buyFee, _sellFee, _transferFee];

        emit liquidityFeesUpdated(_buyFee, _sellFee, _transferFee);
    }

    function excludeFromFees(address account, bool isExcluded) public onlyOwner {
        isExcludedFromFees[account] = isExcluded;
        
        emit ExcludeFromFees(account, isExcluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (!_swapping && amount > 0 && to != address(routerV2) && !isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            uint256 fees = 0;
            uint8 txType = 3;
            
            if (AMMPairs[from]) {
                if (totalFees[0] > 0) txType = 0;
            }
            else if (AMMPairs[to]) {
                if (totalFees[1] > 0) txType = 1;
            }
            else if (totalFees[2] > 0) txType = 2;
            
            if (txType < 3) {
                
                fees = amount * totalFees[txType] / 10000;
                amount -= fees;
                
                _walletPending += fees * walletFees[txType] / totalFees[txType];

                _liquidityPending += fees * liquidityFees[txType] / totalFees[txType];

                
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
        }
        
        bool canSwap = getAllPending() >= getSwapThresholdAmount() && balanceOf(pairV2) > 0;
        
        if (!_swapping && !AMMPairs[from] && from != address(routerV2) && canSwap) {
            _swapping = true;
            
            if (false || _walletPending > 0) {
                uint256 token2Swap = 0 + _walletPending;
                bool success = false;

                _swapTokensForCoin(token2Swap);
                uint256 coinsReceived = address(this).balance;
                
                uint256 walletPortion = coinsReceived * _walletPending / token2Swap;
                if (walletPortion > 0) {
                    success = payable(walletAddress).send(walletPortion);
                    if (success) {
                        emit walletFeeSent(walletAddress, walletPortion);
                    }
                }
                _walletPending = 0;

            }

            if (_liquidityPending > 0) {
                _swapAndLiquify(_liquidityPending);
                _liquidityPending = 0;
            }

            _swapping = false;
        }

        super._transfer(from, to, amount);
        
    }

    function _updateRouterV2(address router) private {
        routerV2 = IUniswapV2Router02(router);
        pairV2 = IUniswapV2Factory(routerV2.factory()).createPair(address(this), routerV2.WETH());
        
        _setAMMPair(pairV2, true);

        emit RouterV2Updated(router);
    }

    function setAMMPair(address pair, bool isPair) external onlyOwner {
        require(pair != pairV2, "DefaultRouter: Cannot remove initial pair from list");

        _setAMMPair(pair, isPair);
    }

    function _setAMMPair(address pair, bool isPair) private {
        AMMPairs[pair] = isPair;

        if (isPair) { 
        }

        emit AMMPairsUpdated(pair, isPair);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "EnableTrading: Trading was enabled already");
        tradingEnabled = true;
        
        emit TradingEnabled();
    }

    function excludeFromTradingRestriction(address account, bool isExcluded) public onlyOwner {
        isExcludedFromTradingRestriction[account] = isExcluded;
        
        emit ExcludeFromTradingRestriction(account, isExcluded);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        // Interactions with DEX are disallowed prior to enabling trading by owner
        if ((AMMPairs[from] && !isExcludedFromTradingRestriction[to]) || (AMMPairs[to] && !isExcludedFromTradingRestriction[from])) {
            require(tradingEnabled, "EnableTrading: Trading was not enabled yet");
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        super._afterTokenTransfer(from, to, amount);
    }
}