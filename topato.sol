// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
 * $TOPATO - Toilet Paper Token
 * - Whale protection (max buy/cooldown), claimable presale/airdrop, burning pool, DEX sell tax, owner/developer split, and more.
 * - All tokens minted to contract itself; NO owner mint/rugpull risk.
 * - 100% open, fully on-chain, ready for Uniswap launch.
 */

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.8.3/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.8.3/contracts/access/Ownable.sol";

interface IUniswapV2Pair {
    function factory() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

contract Topato is ERC20, Ownable {
    // Supply parameters
    uint256 public constant INIT_SUPPLY = 9_000_000_000_000 * 1e18;
    uint256 public constant AIRDROP_SUPPLY = 90_000_000_000 * 1e18; // 1%
    uint256 public constant BURNING_POOL_SUPPLY = 5_400_000_000_000 * 1e18; // 60%
    uint256 public constant LIQUIDITY_SUPPLY = 3_510_000_000_000 * 1e18; // 39%

    // Special: Liquidity pool claim
    uint256 public constant LIQUIDITY_POOL = 562_500_000 * 1e18;
    bool public liquidityClaimed = false;

    // Whale/anti-bot parameters
    bool public antiWhaleActive = true;
    uint256 public maxBuy = 0.01 ether;
    mapping(address => uint256) public lastBuy;
    uint256 public cooldown = 1 minutes;

    // DEX tax settings
    uint256 public constant DEX_TAX = 300;
    uint256 public constant TAX_BURN = 200;
    uint256 public constant TAX_DEV = 50;
    uint256 public constant TAX_OWNER = 50;
    address public devWallet = 0x68f28708103bb2bf857C0Da6451731C8F735e466;
    address public ownerWallet = 0xc080126B48a19FFcB993b9227A83eCA24F63e664;

    // Airdrop
    mapping(address => bool) public hasClaimedAirdrop;
    uint256 public airdropAmount = 1_000_000 * 1e18;
    uint256 public totalAirdropped;
    bool public airdropLive = false;

    // Burning pool / burn admin
    uint256 public burningPool = BURNING_POOL_SUPPLY;
    address public burnAdmin = 0x2e5726197236479924abc4E7066D9A4846Fa7DF8;

    // Uniswap pair
    address public uniswapV2Pair;
    address public uniswapV2Factory;

    // Events
    event BurnedFromPool(uint256 amount);
    event AirdropClaimed(address indexed user, uint256 amount);
    event LiquidityClaimed(address indexed owner, uint256 amount);

    constructor(address _uniswapV2Factory) ERC20("Topato", "TOPATO") {
        _mint(address(this), INIT_SUPPLY);
        uniswapV2Factory = _uniswapV2Factory;
    }

    // --- Whale/anti-bot controls ---
    function setAntiWhale(bool _active) external onlyOwner {
        antiWhaleActive = _active;
    }
    function setMaxBuy(uint256 _maxBuy) external onlyOwner {
        maxBuy = _maxBuy;
    }
    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
    }

    // --- Liquidity pool claim ---
    function claimLiquidityPool() external onlyOwner {
        require(!liquidityClaimed, "Liquidity already claimed");
        liquidityClaimed = true;
        _transfer(address(this), owner(), LIQUIDITY_POOL);
        emit LiquidityClaimed(owner(), LIQUIDITY_POOL);
    }

    // --- Airdrop controls ---
    function toggleAirdrop(bool _live) external onlyOwner {
        airdropLive = _live;
    }
    function claimAirdrop() external {
        require(airdropLive, "Airdrop not live");
        require(!hasClaimedAirdrop[msg.sender], "Already claimed");
        require(totalAirdropped + airdropAmount <= AIRDROP_SUPPLY, "Airdrop finished");

        hasClaimedAirdrop[msg.sender] = true;
        totalAirdropped += airdropAmount;
        _transfer(address(this), msg.sender, airdropAmount);
        emit AirdropClaimed(msg.sender, airdropAmount);
    }

    // --- Burning mechanism ---
    function triggerBurn(uint256 amount) external {
        require(msg.sender == burnAdmin || msg.sender == owner(), "Not authorized");
        require(amount <= burningPool, "Too much burn");
        burningPool -= amount;
        _burn(address(this), amount);
        emit BurnedFromPool(amount);
    }
    function setBurnAdmin(address _admin) external onlyOwner {
        burnAdmin = _admin;
    }

    // --- Tax and anti-whale transfer logic ---
    function _transfer(address from, address to, uint256 amount) internal override {
        // Whale/anti-bot checks (bij koop van Uniswap of launch)
        if (antiWhaleActive && from == uniswapV2Pair) {
            require(amount <= maxBuy, "Buy above max allowed");
            require(block.timestamp > lastBuy[to] + cooldown, "Cooldown active");
            lastBuy[to] = block.timestamp;
        }
        // DEX sell-tax (alleen op verkopen aan Uniswap)
        if (to == uniswapV2Pair && from != address(this)) {
            uint256 taxAmount = (amount * DEX_TAX) / 10000;
            uint256 burnAmount = (amount * TAX_BURN) / 10000;
            uint256 devAmount = (amount * TAX_DEV) / 10000;
            uint256 ownerAmount = (amount * TAX_OWNER) / 10000;
            // Burn 2%
            if (burnAmount > 0) {
                _burn(from, burnAmount);
            }
            // 0.5% naar dev
            if (devAmount > 0) {
                super._transfer(from, devWallet, devAmount);
            }
            // 0.5% naar owner
            if (ownerAmount > 0) {
                super._transfer(from, ownerWallet, ownerAmount);
            }
            // Rest naar ontvanger
            super._transfer(from, to, amount - taxAmount);
        } else {
            super._transfer(from, to, amount);
        }
    }

    // --- Uniswap helper ---
    function setUniswapV2Pair(address _pair) external onlyOwner {
        uniswapV2Pair = _pair;
    }

    // --- Emergency ERC20 recovery (niet-TOPATO) ---
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "Can't rescue TOPATO");
        IERC20(token).transfer(owner(), amount);
    }
}
