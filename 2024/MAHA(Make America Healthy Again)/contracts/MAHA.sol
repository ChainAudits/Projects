// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/*
    www.mahamemecoin.org
    t.me/mahamemecoin
*/

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

interface IFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
    function factory() external view returns (address);

    function WETH() external view returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
    external
    payable
    returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    );

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETH is IERC20 {
    function withdraw(uint256) external;
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
        // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

contract MAHA is ERC20, Ownable {

    modifier lockTaxProcessing() {
        processing = true;
        _;
        processing = false;
    }

    bool private processing = false;

    IRouter public router;
    mapping(address => bool) public amm;

    uint256 public buyTax;
    uint256 public sellTax;

    bool public takingTax = true;
    bool public isCheckingLaunchLimits = true;

    address public taxWallet;

    mapping(address => bool) public excludedFromLimitsChecking;

    bool public swapping = false;

    event PairSet(address indexed pairAddress, bool isAMM);
    event SwappingEnabled();
    event NewTaxWalletSet(address newTaxWallet);
    event LimitsRemoved();
    event TaxSet(uint256 buyFee, uint256 sellFee);
    event TakingTaxDisabled();
    event DoneProcessing();
    event ExcludedAddressSet(address indexed excludedAddress, bool isExcluded);

    constructor(address routerAddress)
    ERC20("Make America Healthy Again", "MAHA")
    {
        _mint(_msgSender(), 100000000 * 1e18);

        excludedFromLimitsChecking[address(_msgSender())] = true;
        excludedFromLimitsChecking[address(this)] = true;

        router = IRouter(routerAddress);
        address _pair = IFactory(router.factory()).createPair(address(this), router.WETH());
        setAMMPair(address(_pair), true);

        taxWallet = address(0x1ECB304cfbdCed37A88bC76966b991aB48526064);

        buyTax = 80000;
        sellTax = 80000;

        excludedFromLimitsChecking[address(router)] = true;
        excludedFromLimitsChecking[address(taxWallet)] = true;
    }

    receive() external payable {}

    function setExcludedAddress(address excludedAddress, bool isExcluded) public onlyOwner {
        require(excludedAddress != address(0), "Address can not be address 0x");
        excludedFromLimitsChecking[excludedAddress] = isExcluded;
        emit ExcludedAddressSet(excludedAddress, isExcluded);
    }

    function setAMMPair(address pairAddress, bool isAMM) public onlyOwner {
        require(pairAddress != address(0), "Pair can not be address 0x");
        amm[pairAddress] = isAMM;
        emit PairSet(pairAddress, isAMM);
    }

    function removeLimits() external onlyOwner {
        require(isCheckingLaunchLimits, "Limits are already removed");
        isCheckingLaunchLimits = false;
        emit LimitsRemoved();
    }

    function setBuyAndSellTax(uint256 newBuyTax, uint256 newSellTax) external onlyOwner {
        require(newBuyTax <= 30000, "Buy tax too high");
        require(newSellTax <= 30000, "Sell tax too high");

        buyTax = newBuyTax;
        sellTax = newSellTax;

        if (newBuyTax == 0 && newSellTax == 0) {
            takingTax = false;
            emit TakingTaxDisabled();
        }

        emit TaxSet(newBuyTax, newSellTax);
    }

    function enableSwap() external onlyOwner {
        require(!swapping, "Swapping is already enabled");
        swapping = true;
        emit SwappingEnabled();
    }

    function setTaxWallet(address newTaxWallet) public onlyOwner {
        require(newTaxWallet != address(0), "Wallet can not be address 0x");
        excludedFromLimitsChecking[address(taxWallet)] = false;
        taxWallet = newTaxWallet;
        excludedFromLimitsChecking[address(newTaxWallet)] = true;
        emit NewTaxWalletSet(newTaxWallet);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(swapping || from == owner(), "Transfers are disabled");

        if (excludedFromLimitsChecking[from] || excludedFromLimitsChecking[to]) {
            super._transfer(from, to, amount);
            return;
        }

        if (isCheckingLaunchLimits) {
            if (amm[from] && !excludedFromLimitsChecking[to]) {
                require(amount <= 500000 * 1e18, "Max transfer exceeded.");
                require(balanceOf(to) + amount <= 1000000 * 1e18, "Max wallet size exceeded.");
            } else if (amm[to] && !excludedFromLimitsChecking[from]) {
                require(amount <= 500000 * 1e18, "Max transfer exceeded.");
            } else if (!excludedFromLimitsChecking[to] && !excludedFromLimitsChecking[from]) {
                require(amount <= 500000 * 1e18, "Max transfer exceeded.");
                require(balanceOf(to) + amount <= 1000000 * 1e18, "Max wallet size exceeded.");
            }
        }

        uint256 _amount = amount;

        if (takingTax) {
            if (amm[from] || amm[to]) {
                uint256 _txnFee;

                if (amm[to]) {
                    _txnFee = (_amount * sellTax) / 100000;

                    if (!processing && balanceOf(address(this)) >= 20000 * 1e18) {
                        startProcessing();
                    }
                }

                if (amm[from]) {
                    _txnFee = (_amount * buyTax) / 100000;
                }

                _amount = _amount - _txnFee;

                super._transfer(from, address(this), _txnFee);
            }
        }

        super._transfer(from, to, _amount);
    }

    function startProcessing() public lockTaxProcessing {
        uint256 _contractBalance = balanceOf(address(this));

        require(_contractBalance != 0, "Contract balance 0");

        uint256 _swapAmount = _contractBalance;

        _swapTokensForEth(_swapAmount);

        uint256 _balance = address(this).balance;

        require(_balance != 0, "ETH balance 0");

        (bool sendSuccess,) = taxWallet.call{value: _balance}("");
        require(sendSuccess, "ETH transfer failed");

        emit DoneProcessing();
    }

    function _swapTokensForEth(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function rescueWETH() external onlyOwner {
        address wethAddress = router.WETH();
        IWETH(wethAddress).withdraw(
            IERC20(wethAddress).balanceOf(address(this))
        );
    }

    function retrieveTokens(address tokenAddress) external onlyOwner {
        IERC20 tokenContract = IERC20(tokenAddress);
        tokenContract.transfer(address(taxWallet), tokenContract.balanceOf(address(this)));
    }

}