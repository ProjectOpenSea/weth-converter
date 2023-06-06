// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {WETH} from "solady/src/tokens/WETH.sol";

import {StdCheats} from "forge-std/StdCheats.sol";

import {AdvancedOrderLib, ConsiderationItemLib, FulfillmentComponentLib, FulfillmentLib, OfferItemLib, OrderComponentsLib, OrderLib, OrderParametersLib, SeaportArrays, ZoneParametersLib} from "seaport-sol/SeaportSol.sol";

import {AdvancedOrder, ConsiderationItem, CriteriaResolver, Fulfillment, FulfillmentComponent, OfferItem, Order, OrderComponents, OrderParameters, ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

import {ItemType, OrderType} from "seaport-types/lib/ConsiderationEnums.sol";

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {WethConverter} from "../src/optimized/WethConverter.sol";

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
    using OrderLib for Order[];
    using OrderParametersLib for OrderParameters;
    using ZoneParametersLib for AdvancedOrder[];

    struct WethContext {
        WethConverter wethConverter;
    }

    address immutable WETH_CONTRACT_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    WETH weth;
    WethConverter wethConverter;

    string constant WETH_OFFER_721_CONSIDERATION = "wethOffer721Consideration";
    string constant GET_ETH_FROM_WETH = "getEthFromWeth";
    string constant GET_WETH_FROM_ETH = "getWethFromEth";

    function setUp() public override {
        super.setUp();

        weth = new WETH();
        wethConverter = new WethConverter(address(seaport), address(weth));

        // Fund weth converter with eth
        vm.deal(address(wethConverter), 1000 ether);

        // Deposit half of eth balance to weth contract
        vm.prank(address(wethConverter));
        IWETH(address(weth)).deposit{value: 500 ether}();

        // Set up and store order with 10 WETH offer for ERC721 consideration
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(address(weth))
            .withAmount(10);
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItemLib
            .empty()
            .withItemType(ItemType.ERC721)
            .withToken(address(erc721s[0]))
            .withAmount(1);
        OrderParameters memory parameters = OrderComponentsLib
            .fromDefault(STANDARD)
            .toOrderParameters()
            .withOffer(offer)
            .withConsideration(consideration);
        OrderLib.empty().withParameters(parameters).saveDefault(
            WETH_OFFER_721_CONSIDERATION
        );

        // Set up and store weth conversion contract order that offers ETH in exchange for WETH
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.NATIVE)
            .withToken(address(0))
            .withAmount(10);
        consideration[0] = ConsiderationItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(address(weth))
            .withAmount(10);
        parameters = OrderComponentsLib
            .fromDefault(STANDARD)
            .toOrderParameters()
            .withOfferer(address(wethConverter))
            .withOffer(offer)
            .withConsideration(consideration);
        OrderLib.empty().withParameters(parameters).saveDefault(
            GET_ETH_FROM_WETH
        );

        // Set up and store weth conversion contract order that offers WETH in exchange for ETH
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(address(weth))
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
        OrderLib.empty().withParameters(parameters).saveDefault(
            GET_WETH_FROM_ETH
        );
    }

    Context context;

    function xtestExecAcceptWethOfferAndGetPaidInEth() public {
        test(this.execAcceptWethOfferAndGetPaidInEth, context);
    }

    function execAcceptWethOfferAndGetPaidInEth(Context memory) external {
        // Mint 721 token to offerer1
        erc721s[0].mint(offerer1.addr, 1);

        Order memory order = OrderLib.fromDefault(WETH_OFFER_721_CONSIDERATION);
        AdvancedOrder memory advancedOrder = order.toAdvancedOrder({
            numerator: 1,
            denominator: 1,
            extraData: bytes("")
        });

        OrderComponents memory orderComponents = advancedOrder
            .parameters
            .toOrderComponents(0);

        // offerer2 makes 10 weth offer for offerer1's NFT
        bytes memory signature = signOrder(
            getSeaport(),
            offerer2.key,
            getSeaport().getOrderHash(orderComponents)
        );

        order = order.withSignature(signature);

        // offerer1 wants to accept the offer but receive eth instead of weth
        Order memory wethConverterOrder = OrderLib.fromDefault(
            GET_ETH_FROM_WETH
        );

        AdvancedOrder[] memory orders = new AdvancedOrder[](2);
        orders[0] = order.toAdvancedOrder({
            numerator: 1,
            denominator: 1,
            extraData: bytes("")
        });

        orders[1] = wethConverterOrder.toAdvancedOrder({
            numerator: 1,
            denominator: 1,
            extraData: bytes("")
        });

        Fulfillment[] memory fulfillments = SeaportArrays.Fulfillments(
            FulfillmentLib.fromDefault(FF_SF),
            FulfillmentLib.fromDefault(SF_FF)
        );

        seaport.matchAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        assert(erc721s[0].ownerOf(1) == address(offerer2.addr));
    }

    function testWethConverter() public {
        test(this.execWethConverter, context);
    }

    function execWethConverter(Context memory) external stateless {
        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](2);
        OrderParameters memory orderParameters;

        // CONVERSION
        vm.deal(address(wethConverter), 4 ether);
        StdCheats.deal(address(weth), address(this), 4 ether);
        weth.approve(address(seaport), 4 ether);

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.NATIVE);
            offerItem = offerItem.withToken(address(0));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(address(weth));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(3 ether);
            considerationItem = considerationItem.withEndAmount(3 ether);
            considerationItem = considerationItem.withRecipient(address(0));

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(
                address(wethConverter)
            );
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[0] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(address(weth));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;
            considerationArray = new ConsiderationItem[](0);
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(address(this));
            orderParameters = orderParameters.withOrderType(
                OrderType.FULL_OPEN
            );
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(0);

            order.withParameters(orderParameters);

            orders[1] = order;
        }

        Fulfillment[] memory fulfillments = new Fulfillment[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsOne = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsTwo = new FulfillmentComponent[](1);

        {
            fulfillmentComponentsOne[0] = FulfillmentComponent(1, 0);
            fulfillmentComponentsTwo[0] = FulfillmentComponent(0, 0);
        }

        fulfillments[0] = Fulfillment(
            fulfillmentComponentsOne,
            fulfillmentComponentsTwo
        );

        uint256 nativeBalanceBefore = address(this).balance;

        seaport.matchAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        uint256 nativeBalanceAfter = address(this).balance;

        assertEq(
            nativeBalanceAfter - nativeBalanceBefore,
            3 ether,
            "native balance should increase by 3 ether"
        );
        assertEq(
            weth.balanceOf(address(this)),
            1 ether,
            "weth balance should be 1 ether"
        );

        ////////////////////////////////////////////////////////////////////////
        ////////////////////////////// BREAK ///////////////////////////////////
        ////////////////////////////////////////////////////////////////////////

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(address(weth));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.NATIVE);
            considerationItem = considerationItem.withToken(address(0));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(3 ether);
            considerationItem = considerationItem.withEndAmount(3 ether);
            considerationItem = considerationItem.withRecipient(address(0));

            considerationArray = new ConsiderationItem[](1);
            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(
                address(wethConverter)
            );
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[0] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.NATIVE);
            offerItem = offerItem.withToken(address(0));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;
            considerationArray = new ConsiderationItem[](0);
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(address(this));
            orderParameters = orderParameters.withOrderType(
                OrderType.FULL_OPEN
            );
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(0);

            order.withParameters(orderParameters);

            orders[1] = order;
        }

        fulfillments = new Fulfillment[](1);
        fulfillmentComponentsOne = new FulfillmentComponent[](1);
        fulfillmentComponentsTwo = new FulfillmentComponent[](1);

        {
            fulfillmentComponentsOne[0] = FulfillmentComponent(1, 0);
            fulfillmentComponentsTwo[0] = FulfillmentComponent(0, 0);
        }

        fulfillments[0] = Fulfillment(
            fulfillmentComponentsOne,
            fulfillmentComponentsTwo
        );

        nativeBalanceBefore = address(this).balance;

        seaport.matchAdvancedOrders{value: 3 ether}(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        nativeBalanceAfter = address(this).balance;

        assertEq(
            nativeBalanceBefore - nativeBalanceAfter,
            3 ether,
            "native balance should decrease by 3 ether"
        );
        assertEq(
            weth.balanceOf(address(this)),
            4 ether,
            "weth balance should be 4 ether"
        );
    }

    function testExecWethConverterMatch() public {
        test(this.execWethConverterMatch, context);
    }

    function execWethConverterMatch(Context memory) external stateless {
        erc721s[0].mint(eve.addr, 0);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        // dillon approves seaport to transfer his weth
        StdCheats.deal(address(weth), dillon.addr, 3 ether);
        vm.prank(dillon.addr);
        weth.approve(address(seaport), 3 ether);

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 3 WETH FOR EVE'S NFT
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(address(weth));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC721);
            considerationItem = considerationItem.withToken(
                address(erc721s[0])
            );
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(1);
            considerationItem = considerationItem.withEndAmount(1);
            considerationItem = considerationItem.withRecipient(dillon.addr);

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(dillon.addr);
            orderParameters = orderParameters.withOrderType(
                OrderType.FULL_OPEN
            );
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[0] = order;

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                dillon.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// WETH CONVERTER ORDER ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.NATIVE);
            offerItem = offerItem.withToken(address(0));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(3 ether);
            offerItem = offerItem.withEndAmount(3 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(address(weth));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(3 ether);
            considerationItem = considerationItem.withEndAmount(3 ether);
            considerationItem = considerationItem.withRecipient(
                address(wethConverter)
            );

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(
                address(wethConverter)
            );
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[1] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// EVE ACCEPTS OFFER AND RECEIVES 3 ETH
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC721);
            offerItem = offerItem.withToken(address(erc721s[0]));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(1);
            offerItem = offerItem.withEndAmount(1);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.NATIVE);
            considerationItem = considerationItem.withToken(address(0));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(3 ether);
            considerationItem = considerationItem.withEndAmount(3 ether);
            considerationItem = considerationItem.withRecipient(eve.addr);

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(eve.addr);
            orderParameters = orderParameters.withOrderType(
                OrderType.FULL_OPEN
            );
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[2] = order;

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                eve.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);
        }

        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        FulfillmentComponent[]
            memory fulfillmentComponentsOne = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsTwo = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsThree = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsFour = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsFive = new FulfillmentComponent[](1);
        FulfillmentComponent[]
            memory fulfillmentComponentsSix = new FulfillmentComponent[](1);

        {
            fulfillmentComponentsOne[0] = FulfillmentComponent(2, 0);
            fulfillmentComponentsTwo[0] = FulfillmentComponent(0, 0);
            fulfillmentComponentsThree[0] = FulfillmentComponent(0, 0);
            fulfillmentComponentsFour[0] = FulfillmentComponent(1, 0);
            fulfillmentComponentsFive[0] = FulfillmentComponent(1, 0);
            fulfillmentComponentsSix[0] = FulfillmentComponent(2, 0);
        }

        fulfillments[0] = Fulfillment(
            fulfillmentComponentsOne,
            fulfillmentComponentsTwo
        );

        fulfillments[1] = Fulfillment(
            fulfillmentComponentsThree,
            fulfillmentComponentsFour
        );

        fulfillments[2] = Fulfillment(
            fulfillmentComponentsFive,
            fulfillmentComponentsSix
        );

        uint256 wethConverterBalanceBefore = weth.balanceOf(
            address(wethConverter)
        );
        assertEq(
            wethConverterBalanceBefore,
            500 ether,
            "weth converter balance should be 500 weth"
        );

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        seaport.matchAdvancedOrders{value: 3 ether}(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        assertEq(erc721s[0].ownerOf(0), dillon.addr, "dillon should own nft");
        assertEq(
            weth.balanceOf(address(wethConverter)) - wethConverterBalanceBefore,
            3 ether,
            "weth converter balance should have increased by 3 ether"
        );
        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            3 ether,
            "eve's balance should have increased by 3 ether"
        );
    }
}
