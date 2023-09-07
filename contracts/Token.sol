// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Router02.sol";
import "./interface/IJackpot.sol";

contract Token is ERC20("NXC", "NXC"), Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => bool) _isExcludedFromFee;
    address payable private _taxWallet;
    uint firstBlock;
    uint8 private constant _decimals = 18;
    uint256 private constant _total = 1000000000 * 10 ** _decimals;
    uint256 public _maxTxAmount = 1000000 * 10 ** _decimals;
    uint256 public _maxWalletSize = 1000000 * 10 ** _decimals;
    uint256 public _taxSwapThreshold = 1000000 * 10 ** _decimals;
    uint256 public _maxTaxSwap = 1000000 * 10 ** _decimals;

    uint256 private _initialBuyTax = 17;
    uint256 private _initialSellTax = 17;
    uint256 private _finalBuyTax = 5;
    uint256 private _finalSellTax = 5;
    uint256 private _reduceBuyTaxAt = 25;
    uint256 private _reduceSellTaxAt = 25;
    uint256 private _preventSwapBefore = 25;
    uint256 private _buyCount = 0;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    address jackpotAddress;

    address private _jackpotmanager;

    constructor() {
        _taxWallet = payable(_msgSender());
        _mint(_msgSender(), _total);
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[_taxWallet] = true;
        emit Transfer(address(0), _msgSender(), _total);
    }

    function jackpotmanager() public view returns (address) {
        return _jackpotmanager;
    }

    modifier onlyJackpotManager() {
        require(
            _jackpotmanager == _msgSender(),
            "Ownable: caller is not the jackpot manager"
        );
        _;
    }

    function renounceJackpotManager() public virtual onlyJackpotManager {
        _jackpotmanager = address(0);
    }

    event MaxTxAmountUpdated(uint _maxTxAmount);
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = 0;
        if (from != owner() && to != owner()) {
            taxAmount =
                (amount *
                    (
                        (_buyCount > _reduceBuyTaxAt)
                            ? _finalBuyTax
                            : _initialBuyTax
                    )) /
                100;

            if (
                from == uniswapV2Pair &&
                to != address(uniswapV2Router) &&
                !_isExcludedFromFee[to]
            ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(
                    balanceOf(to) + amount <= _maxWalletSize,
                    "Exceeds the maxWalletSize."
                );

                if (firstBlock + 3 > block.number) {
                    require(!isContract(to));
                }
                _buyCount++;
            }

            if (to != uniswapV2Pair && !_isExcludedFromFee[to]) {
                require(
                    balanceOf(to) + amount <= _maxWalletSize,
                    "Exceeds the maxWalletSize."
                );
            }

            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount =
                    (amount *
                        (
                            (_buyCount > _reduceBuyTaxAt)
                                ? _finalBuyTax
                                : _initialBuyTax
                        )) /
                    100;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                !inSwap &&
                to == uniswapV2Pair &&
                swapEnabled &&
                contractTokenBalance > _taxSwapThreshold &&
                _buyCount > _preventSwapBefore
            ) {
                swapTokensForEth(
                    min(amount, min(contractTokenBalance, _maxTaxSwap))
                );
                uint256 contractETHBalance = balanceOf(address(this));
                if (contractETHBalance > 0) {
                    Jackpot(jackpotAddress).addBonus{
                        value: (address(this).balance / 2)
                    }(); //send 50% to bonus pool jackpot
                    sendETHToFee(balanceOf(address(this))); //send 50% to tax wallet
                }
            }
        }

        if (taxAmount > 0) {
            _balances[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] -= amount;
        _balances[to] += (amount - taxAmount);

        emit Transfer(from, to, (amount - taxAmount));
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function setJackpotAddress(
        address _jackpotAddress
    ) external onlyJackpotManager {
        jackpotAddress = _jackpotAddress;
    }

    function removeLimits() external onlyOwner {
        _maxTxAmount = _total;
        _maxWalletSize = _total;
        emit MaxTxAmountUpdated(_total);
    }

    function sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    function openTrading() external onlyOwner {
        require(!tradingOpen, "trading is already open");
        uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(uniswapV2Router), _total);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
                address(this),
                uniswapV2Router.WETH()
            );
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        swapEnabled = true;
        tradingOpen = true;
        firstBlock = block.number;
    }

    receive() external payable {}
}
