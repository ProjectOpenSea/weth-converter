// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    AdvancedOrderLib,
    ConsiderationItemLib,
    FulfillmentComponentLib,
    FulfillmentLib,
    OfferItemLib,
    OrderComponentsLib,
    OrderLib,
    OrderParametersLib,
    SeaportArrays,
    ZoneParametersLib
} from "seaport-sol/SeaportSol.sol";

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {WethConverter} from "../src/optimized/WethConverter.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

contract WethConverterTest is BaseOrderTest {
    using AdvancedOrderLib for AdvancedOrder;
    using AdvancedOrderLib for AdvancedOrder[];
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using FulfillmentComponentLib for FulfillmentComponent;
    using FulfillmentComponentLib for FulfillmentComponent[];
    using FulfillmentLib for Fulfillment;
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using OrderComponentsLib for OrderComponents;
    using OrderLib for Order;
    using OrderParametersLib for OrderParameters;
    using ZoneParametersLib for AdvancedOrder[];

    struct Context {
        WethConverter wethConverter;
        bool isReference;
    }

    address immutable WETH_CONTRACT_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    WethConverter wethConverter;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    function setUp() public override {
        super.setUp();

        wethConverter = WethConverter(
            deployCode("out/WethConverter.sol/WethConverter.json", abi.encode(address(consideration), WETH_CONTRACT_ADDRESS))
        );

        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();

        // Fund weth converter with eth
        vm.deal(address(wethConverter), 1000 ether);

        // Deposit half of eth balance to weth contract
        vm.prank(address(wethConverter));
        IWETH(WETH_CONTRACT_ADDRESS).deposit{value: 500 ether}();

        // Set up and store order with 10 WETH offer for ERC721 consideration
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(WETH_CONTRACT_ADDRESS)
            .withAmount(10);
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItemLib
            .empty()
            .withItemType(ItemType.ERC721)
            .withToken(address(testERC721))
            .withAmount(1);
        OrderParameters memory parameters = OrderComponentsLib
            .fromDefault(STANDARD)
            .toOrderParameters()
            .withOffer(offer)
            .withConsideration(consideration);
        OrderLib.empty().withParameters(parameters).saveDefault(WETH_OFFER_721_CONSIDERATION);

        // Set up and store weth conversion contract order that offers ETH in exchange for WETH
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.NATIVE)
            .withToken(address(0))
            .withAmount(10);
        consideration[0] = ConsiderationItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(WETH_CONTRACT_ADDRESS)
            .withAmount(10);
        parameters = OrderComponentsLib
            .fromDefault(STANDARD)
            .toOrderParameters()
            .withOfferer(address(wethConverter))
            .withOffer(offer)
            .withConsideration(consideration);
        OrderLib.empty().withParameters(parameters).saveDefault(GET_ETH_FROM_WETH);

        // Set up and store weth conversion contract order that offers WETH in exchange for ETH
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(WETH_CONTRACT_ADDRESS)
            .withAmount(10);
        consideration[0] = ConsiderationItemLib
            .empty()
            .withItemType(ItemType.NATIVE)
            .withToken(address(0))
            .withAmount(10);
        parameters = OrderComponentsLib
            .fromDefault(STANDARD)
            .toOrderParameters()
            .withOfferer(address(wethConverter))
            .withOffer(offer)
            .withConsideration(consideration);
        OrderLib.empty().withParameters(parameters).saveDefault(GET_WETH_FROM_ETH);
    }

    function test(function(Context memory) external fn, Context memory context) internal {
        try fn(context) {
            fail("Stateless test function should have reverted with assertion failure status.");
        } catch (bytes memory reason) {
            assertPass(reason);
        }
    }

    function testExecAcceptWethOfferAndGetPaidInEth() public {
        test(this.execAcceptWethOfferAndGetPaidInEth, Context({isReference: false}));
    }

    function execAcceptWethOfferAndGetPaidInEth(Context memory context) external {
        // Mint 721 token to offerer1
        testERC721.mint(offerer1.addr, 1);
        
        // offerer2 makes 10 weth offer for offerer1's NFT
        bytes memory signature = signOrder(
            getSeaport(),
            offerer2.key,
            getSeaport().getOrderHash(orderComponents)
        );

        Order memory order = OrderLib
            .fromDefault(WETH_OFFER_721_CONSIDERATION)
            .withSignature(signature);

        // offerer1 wants to accept the offer but receive eth instead of weth
        Order memory wethConverterOrder = OrderLib.fromDefault(GET_ETH_FROM_WETH);

        AdvancedOrder[] memory orders = new AdvancedOrder[](2);
        orders[0] = order.toAdvancedOrder({
            numerator: 0,
            denominator: 0,
            extraData: bytes("")
        });

        orders[1] = wethConverterOrder.toAdvancedOrder({
            numerator: 0,
            denominator: 0,
            extraData: bytes("")
        });

        fulfillments = SeaportArrays.Fulfillments(
            FulfillmentLib.fromDefault(FF_SF),
            FulfillmentLib.fromDefault(SF_FF)
        );

        seaport.matchAdvancedOrders(orders, new CriteriaResolver[](0), fulfillments, address(0));

        assert(testERC721.ownerOf(1) == address(offerer2.addr));
    }   
}
