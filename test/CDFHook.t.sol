// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import "../src/CryptoIndexToken.sol";
import "../src/CDPManager.sol";
import "../src/CDPHook.sol";
import "v4-core/PoolManager.sol";
import "v4-core/interfaces/IPoolManager.sol";
import "v4-core/types/Currency.sol";
import "v4-core/types/PoolKey.sol";
import "v4-core/libraries/TickMath.sol";
import "solmate/src/tokens/ERC20.sol";
import "solmate/src/test/utils/mocks/MockERC20.sol";
import "chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import "forge-std/console.sol";

contract CDPSystemTest is Test, Deployers {
    MockERC20 usdc;
    CryptoIndexToken cit;
    CDPManager cdpManager;
    CDPHook hook;
    IPoolManager.SwapParams swapParams;
    Currency usdcCurrency;
    Currency citCurrency;
    PoolKey poolKey;
    MockV3Aggregator oracle;

    function setUp() public {
        // Deploy Pool Manager using Deployers utility
        deployFreshManagerAndRouters();

        // Deploy USDC Mock Token
        usdc = new MockERC20("Mock USDC", "USDC", 6);
        usdc.mint(address(this), 10_000e6);

        // Approve USDC Mock
        usdc.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        usdc.approve(address(hook), type(uint256).max);

        // Deploy Mock Oracle
        oracle = new MockV3Aggregator(18, 1000e18); // Assume CIT price is $1000, 18 decimals

        // Deploy Hook
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo("CDPHook.sol", abi.encode(manager), address(flags));
        hook = CDPHook(address(flags));

        // Deploy CDP Manager, pass the hook's address
        cdpManager = new CDPManager(
            address(usdc),
            address(oracle),
            address(hook)
        );
        usdc.approve(address(cdpManager), type(uint256).max);

        // Now set the CDP Manager's address in the Hook
        hook.setCDPManager(address(cdpManager));

        // Predict the CIP token address generated by CREATE2
        bytes32 salt = keccak256(abi.encodePacked("unique_identifier"));
        bytes memory bytecode = type(CryptoIndexToken).creationCode;
        bytes32 bytecodeHash = cdpManager.getBytecodeHash(bytecode);
        address predictedCitAddress = cdpManager.computeAddress(salt, bytecodeHash);
        cit = CryptoIndexToken(predictedCitAddress);

        // Wrap currency for the pool
        usdcCurrency = Currency.wrap(address(usdc));
        citCurrency = Currency.wrap(address(cit));

        // Initialize a pool
        (key, ) = initPool(
            usdcCurrency, // Currency 0 = USDC
            citCurrency, // Currency 1 = CIT
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        cit.approve(address(swapRouter), type(uint256).max);
        cit.approve(address(modifyLiquidityRouter), type(uint256).max);
        cit.approve(address(hook), type(uint256).max);

        hook.addLiquidity(key, 1000e6);

        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: -60,
        //         tickUpper: 60,
        //         liquidityDelta: 100 ether,
        //         salt: bytes32(0)
        //     }),
        //     ZERO_BYTES
        // );
    }

    function testAddLiquidityAndMintCIT() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        // uint256 usdcToAdd = 1000e6;
        // uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
        //     sqrtPriceAtTickLower,
        //     SQRT_PRICE_1_1,
        //     usdcToAdd
        // );
        // console.logInt(int256(int128(liquidityDelta)));

        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: -60,
        //         tickUpper: 60,
        //         liquidityDelta: int256(uint256(liquidityDelta)),
        //         salt: bytes32(0)
        //     }),
        //     hookData
        // );

        // uint256 usdcAmount = 100e6; // 100 USDC
        // // Prepare ModifyLiquidityParams
        // IPoolManager.ModifyLiquidityParams memory params = IPoolManager
        //     .ModifyLiquidityParams({
        //         tickLower: -60,
        //         tickUpper: 60,
        //         liquidityDelta: int128(1000000),
        //         salt: bytes32(0)
        //     });
        // // Call modifyLiquidity on Pool Manager
        // manager.modifyLiquidity(poolKey, params, "");
        // // Verify CIT minted to user
        // uint256 citBalance = cit.balanceOf(address(this));
        // assertTrue(citBalance > 0, "CIT not minted");
        // // Capture the returned values
        // (uint256 collateral, uint256 debt) = cdpManager.positions(
        //     address(this)
        // );
        // // Verify user's position in CDP Manager
        // assertEq(collateral, usdcAmount, "Incorrect collateral");
        // assertEq(debt, citBalance, "Incorrect debt");
    }
}
