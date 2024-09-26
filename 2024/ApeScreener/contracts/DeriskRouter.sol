// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IDEXRouter.sol";
import "./interfaces/IDEXFactory.sol";
import "./interfaces/IDEXPair.sol";
import "./interfaces/IERC20.sol";

interface IStaking {
    function stakedBalanceOf(address account) external view returns (uint256);
}

contract DeriskRouter {
    
    using ECDSA for bytes32;
    using Address for address payable;
    IDEXRouter private constant uniswapV2Router = IDEXRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private constant factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 private constant APES = IERC20(0x09675e24CA1EB06023451AC8088EcA1040F47585);
    uint256 private constant FEE_CAP = 500;

    address payable public owner;
    address payable public feeCollector; 
    mapping(address => bool) public isExecutor;
    mapping(address => mapping(address => uint256)) public lastExecutedNonce;    
    address public stakingContract;
    uint256[3] public tiers = [1250000 * 10**18, 250000 * 10**18, 100000 * 10**18];
    uint256[4] public feesPerTier = [0, 25, 50, 100];
    

    bytes32 public DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256("Apescreener"),
        keccak256("1"),
        block.chainid,
        address(this)
      )
    );
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Data(address wallet,address token,uint256 nonce,uint256 deadline)");

    event Derisked(address wallet, address token, uint256 nonce);

    error INVALID_SIGNATURE();
    error ORDER_EXPIRED();
    error ORDER_ALREADY_EXECUTED();
    error NOT_AUTHORIZED();
    error INVALID_TX();
    error INVALID_ADDRESS();

    constructor(address payable _owner) {
        owner = payable(_owner);
        feeCollector = _owner;
        isExecutor[msg.sender] = true;
    }

    function derisk(address payable userWallet, address token, uint256 nonce, uint256 signatureDeadline, uint256 amountIn, uint256 minAmountOut, bytes calldata signature) external { 
        uint256 gasFees;
        uint256 gasLimit = gasleft() + 25000;
        if (msg.sender != userWallet) {
            gasFees = gasLimit * tx.gasprice; // test with all kind of txs
            if (lastExecutedNonce[userWallet][token] >= nonce) revert ORDER_ALREADY_EXECUTED(); //this makes sure that the nonce is always increasing
            if (!isExecutor[msg.sender]) revert NOT_AUTHORIZED();
            if (signatureDeadline < block.timestamp) revert ORDER_EXPIRED();
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, userWallet, token, nonce, signatureDeadline))));
            address recoveredAddress = digest.recover(signature);
            if (recoveredAddress != userWallet) revert INVALID_SIGNATURE();
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        _swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, userWallet);

        uint256 fees = address(this).balance * getFeesBps(userWallet) / 10000;

        feeCollector.sendValue(fees + gasFees);
        userWallet.sendValue(address(this).balance);
        lastExecutedNonce[userWallet][token] = nonce;
        emit Derisked(userWallet, token, nonce);
    }

    function getFeesBps(address userWallet) public view returns (uint256) {
        uint256 balanceUser = APES.balanceOf(userWallet);
        if (stakingContract != address(0)) {
            balanceUser += IStaking(stakingContract).stakedBalanceOf(userWallet);
        }

        if (balanceUser > tiers[0]) {
            return feesPerTier[0];
        } else  if (balanceUser > tiers[1]) {
            return feesPerTier[1];
        } else if (balanceUser > tiers[2]) {
            return feesPerTier[2];
        } else {
            return feesPerTier[3];
        }
    }

    function _swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address userWallet
    )
        internal
    {
        address pair = IDEXFactory(factory).getPair(path[0], path[1]);
        _safeTransferFrom(path[0], userWallet, pair, amountIn);
        
        _swapSupportingFeeOnTransferTokens(path, IDEXPair(pair));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IERC20(WETH).withdraw(amountOut);
    }


    function _swapSupportingFeeOnTransferTokens(address[] memory path, IDEXPair pair) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = _sortTokens(input, output);

            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
            amountOutput = uniswapV2Router.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'transferFrom failed'
        );
    }

    function setStakingContract(address _stakingContract) external {
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        stakingContract = _stakingContract;
    }

    function setFeeCollector(address payable _feeCollector) external {
        if (_feeCollector == address(0)) revert INVALID_ADDRESS();
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        feeCollector = _feeCollector;
    }

    function setExecutor(address executor, bool value) external {
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        isExecutor[executor] = value;
    }

    function setOwner(address payable newOwner) external {
        if (newOwner == address(0)) revert INVALID_ADDRESS();
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        owner = newOwner;
    }

    function setTiers(uint256 _tiers1, uint256 _tiers2, uint256 _tiers3) external {
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        tiers = [_tiers1 * 10**18, _tiers2 * 10**18, _tiers3 * 10**18];
    }

    function setFees(uint256 _fee1, uint256 _fee2, uint256 _fee3, uint256 _fee4) external {
        if (msg.sender != owner) revert NOT_AUTHORIZED();
        require(_fee1 <= FEE_CAP && _fee2 <= FEE_CAP && _fee3 <= FEE_CAP && _fee4 <= FEE_CAP, "Fees must be less than 500 bps");
        feesPerTier = [_fee1, _fee2, _fee3, _fee4];
    }

    receive() external payable {}
}