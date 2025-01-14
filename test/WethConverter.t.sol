// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WETH } from "solady/src/tokens/WETH.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

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

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    Order,
    OrderComponents,
    OrderParameters,
    ReceivedItem,
    Schema,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import { ItemType, OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

import {
    ContractOffererInterface
} from "seaport-types/interfaces/ContractOffererInterface.sol";

import { WethConverter } from "../src/optimized/WethConverter.sol";

import { BaseOrderTest } from "./utils/BaseOrderTest.sol";

import {
    ReceivedItem,
    Schema,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

struct Condition {
    bytes32 orderHash;
    uint256 amount;
    uint256 startTime;
    uint256 endTime;
    uint120 fractionToFulfill;
    uint120 totalSize;
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

    address immutable wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IWETH weth;
    WethConverter wethConverter;
    Context context;

    string constant WETH_OFFER_721_CONSIDERATION = "wethOffer721Consideration";
    string constant GET_ETH_FROM_WETH = "getEthFromWeth";
    string constant GET_WETH_FROM_ETH = "getWethFromEth";

    function setUp() public override {
        super.setUp();
        vm.chainId(1);

        bytes memory wethCode = address(new WETH()).code;
        vm.etch(wethAddress, wethCode);
        weth = IWETH(wethAddress);

        wethConverter = new WethConverter(address(seaport));

        // Fund weth converter with eth
        vm.deal(address(wethConverter), 1000 ether);

        // Deposit half of eth balance to weth contract
        vm.prank(address(wethConverter));
        weth.deposit{ value: 500 ether }();

        // Accounts approve seaport to transfer weth
        StdCheats.deal(wethAddress, dillon.addr, 1000 ether);
        vm.prank(dillon.addr);
        weth.approve(address(seaport), type(uint256).max);

        StdCheats.deal(wethAddress, eve.addr, 1000 ether);
        vm.prank(eve.addr);
        weth.approve(address(seaport), type(uint256).max);

        StdCheats.deal(wethAddress, frank.addr, 1000 ether);
        vm.prank(frank.addr);
        weth.approve(address(seaport), type(uint256).max);

        // Set up and store order with 10 WETH offer for ERC721 consideration
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItemLib
            .empty()
            .withItemType(ItemType.ERC20)
            .withToken(wethAddress)
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
            .withToken(wethAddress)
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
            .withToken(wethAddress)
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
        StdCheats.deal(wethAddress, address(this), 4 ether);
        IWETH(wethAddress).approve(address(seaport), 4 ether);

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
            considerationItem = considerationItem.withToken(wethAddress);
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
            offerItem = offerItem.withToken(wethAddress);
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
            offerItem = offerItem.withToken(wethAddress);
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

        seaport.matchAdvancedOrders{ value: 3 ether }(
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

    function testExecAcceptWethOfferAndGetPaidInEth() public {
        test(this.execAcceptWethOfferAndGetPaidInEth, context);
    }

    function execAcceptWethOfferAndGetPaidInEth(
        Context memory
    ) external stateless {
        erc721s[0].mint(eve.addr, 0);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 3 WETH FOR EVE'S NFT
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
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
            considerationItem = considerationItem.withToken(wethAddress);
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

        seaport.matchAdvancedOrders(
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

    function testExecAcceptWethOfferAndFulfillErc721Listing() public {
        test(this.execAcceptWethOfferAndFulfillErc721Listing, context);
    }

    function execAcceptWethOfferAndFulfillErc721Listing(
        Context memory
    ) external stateless {
        erc721s[0].mint(eve.addr, 0);
        erc721s[0].mint(frank.addr, 1);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](4);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 5 WETH FOR EVE'S NFT
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(5 ether);
            offerItem = offerItem.withEndAmount(5 ether);

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

        /// WETH CONVERTER OFFERS 5 ETH AND CONSIDERS 5 WETH ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.NATIVE);
            offerItem = offerItem.withToken(address(0));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(5 ether);
            offerItem = offerItem.withEndAmount(5 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(5 ether);
            considerationItem = considerationItem.withEndAmount(5 ether);
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

        /// EVE OFFERS NFT, NO CONSIDERATION ITEMS ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC721);
            offerItem = offerItem.withToken(address(erc721s[0]));
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(1);
            offerItem = offerItem.withEndAmount(1);

            offerArray[0] = offerItem;
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
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(0);

            order.withParameters(orderParameters);

            orders[2] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// FRANK LISTS ERC721 FOR 3 ETH ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC721);
            offerItem = offerItem.withToken(address(erc721s[0]));
            offerItem = offerItem.withIdentifierOrCriteria(1);
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
            considerationItem = considerationItem.withRecipient(frank.addr);

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(frank.addr);
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

            orders[3] = order;

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                frank.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);
        }

        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        {
            FulfillmentComponent[]
                memory fulfillmentComponentsOne = new FulfillmentComponent[](1);
            FulfillmentComponent[]
                memory fulfillmentComponentsTwo = new FulfillmentComponent[](1);
            FulfillmentComponent[]
                memory fulfillmentComponentsThree = new FulfillmentComponent[](
                    1
                );
            FulfillmentComponent[]
                memory fulfillmentComponentsFour = new FulfillmentComponent[](
                    1
                );
            FulfillmentComponent[]
                memory fulfillmentComponentsFive = new FulfillmentComponent[](
                    1
                );
            FulfillmentComponent[]
                memory fulfillmentComponentsSix = new FulfillmentComponent[](1);

            // Order 1 - dillon's offer
            // Offer: 5 WETH
            // Consideration: NFT #0

            // Order 2 - weth converter
            // Offer: 5 ETH
            // Consideration: 5 WETH

            // Order 3 - eve's offer
            // Offer: NFT #0

            // Order 4 - frank's listing
            // Offer: NFT #1
            // Consideration: 3 ETH

            fulfillmentComponentsOne[0] = FulfillmentComponent(0, 0); // dillon's 5 weth offer
            fulfillmentComponentsTwo[0] = FulfillmentComponent(1, 0); // weth converter 5 weth consideration
            fulfillmentComponentsThree[0] = FulfillmentComponent(1, 0); // weth converter 5 eth offer
            fulfillmentComponentsFour[0] = FulfillmentComponent(3, 0); // frank's 3 eth consideration
            fulfillmentComponentsFive[0] = FulfillmentComponent(2, 0); // eve's nft #0 offer
            fulfillmentComponentsSix[0] = FulfillmentComponent(0, 0); // dillon's nft #0 consideration

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
        }

        uint256 wethConverterBalanceBefore = weth.balanceOf(
            address(wethConverter)
        );
        assertEq(
            wethConverterBalanceBefore,
            500 ether,
            "weth converter balance should be 500 weth"
        );

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 frankNativeBalanceBefore = frank.addr.balance;

        vm.prank(eve.addr);
        seaport.matchAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        assertEq(erc721s[0].ownerOf(0), dillon.addr, "dillon should own nft 0");
        assertEq(erc721s[0].ownerOf(1), eve.addr, "eve should own nft 1");
        assertEq(
            weth.balanceOf(address(wethConverter)) - wethConverterBalanceBefore,
            5 ether,
            "weth converter balance should have increased by 5 ether"
        );
        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            2 ether,
            "eve's balance should have increased by 2 ether"
        );
        assertEq(
            frank.addr.balance - frankNativeBalanceBefore,
            3 ether,
            "frank's balance should have increased by 3 ether"
        );
    }

    function testExecFulfillAvailableWithUnavailableOrder() public {
        test(this.execFulfillAvailableWithUnavailableOrder, context);
    }

    function execFulfillAvailableWithUnavailableOrder(
        Context memory
    ) external stateless {
        erc721s[0].mint(eve.addr, 0);
        erc721s[0].mint(eve.addr, 1);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// WETH CONVERTER OFFERS NOTHING AND CONSIDERS 3 WETH ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
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

            orders[0] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 1 WETH FOR EVE'S NFT TOKENID 0
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(1 ether);
            offerItem = offerItem.withEndAmount(1 ether);

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

            orders[1] = order;

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

        /// FRANK OFFERS 2 WETH FOR EVE'S NFT TOKENID 1 ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(2 ether);
            offerItem = offerItem.withEndAmount(2 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC721);
            considerationItem = considerationItem.withToken(
                address(erc721s[0])
            );
            considerationItem = considerationItem.withIdentifierOrCriteria(1);
            considerationItem = considerationItem.withStartAmount(1);
            considerationItem = considerationItem.withEndAmount(1);
            considerationItem = considerationItem.withRecipient(frank.addr);

            considerationArray[0] = considerationItem;
        }

        {
            orderParameters = OrderParametersLib.empty();
            orderParameters = orderParameters.withOfferer(frank.addr);
            orderParameters = orderParameters.withOrderType(
                OrderType.FULL_OPEN
            );
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 1);
            orderParameters = orderParameters.withOffer(offerArray);
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(0);

            order.withParameters(orderParameters);

            orders[2] = order;

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                frank.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);
        }

        // Add conditions to weth converter order's extraData
        {
            Condition[] memory conditions = new Condition[](2);

            OrderParameters memory orderParametersOne = orders[1].parameters;
            OrderParameters memory orderParametersTwo = orders[2].parameters;

            // add the other two orders' orderHashes to extraData
            bytes32 orderHashOne = seaport.getOrderHash(
                orderParametersOne.toOrderComponents(0)
            );

            bytes32 orderHashTwo = seaport.getOrderHash(
                orderParametersTwo.toOrderComponents(0)
            );

            conditions[0] = Condition({
                orderHash: orderHashOne,
                amount: orderParametersOne.offer[0].startAmount,
                startTime: orderParametersOne.startTime,
                endTime: orderParametersOne.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            conditions[1] = Condition({
                orderHash: orderHashTwo,
                amount: orderParametersTwo.offer[0].startAmount,
                startTime: orderParametersTwo.startTime,
                endTime: orderParametersTwo.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            bytes memory extraData = abi.encodePacked(
                uint8(0),
                abi.encode(conditions)
            );

            orders[0].extraData = extraData;
        }

        // Frank cancels his order before eve submits
        OrderComponents[] memory orderThreeComponents = new OrderComponents[](
            1
        );
        orderThreeComponents[0] = orders[2].parameters.toOrderComponents(0);
        vm.prank(frank.addr);
        seaport.cancel(orderThreeComponents);

        (
            FulfillmentComponent[][] memory offerFulfillmentComponents,
            FulfillmentComponent[][] memory considerationFulfillmentComponents
        ) = fulfill.getAggregatedFulfillmentComponents(orders);

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 eveWethBalanceBefore = weth.balanceOf(eve.addr);

        uint256 frankWethBalanceBefore = weth.balanceOf(frank.addr);

        uint256 dillonWethBalanceBefore = weth.balanceOf(dillon.addr);

        uint256 wethConverterWethBalanceBeore = weth.balanceOf(
            address(wethConverter)
        );

        uint256 wethConverterNativeBalanceBefore = address(wethConverter)
            .balance;

        // eve submits her order
        vm.prank(eve.addr);
        seaport.fulfillAvailableAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            offerFulfillmentComponents,
            considerationFulfillmentComponents,
            bytes32(0),
            address(0),
            100
        );

        assertEq(
            erc721s[0].ownerOf(1),
            eve.addr,
            "eve should still own token 1"
        );

        assertEq(
            eveWethBalanceBefore,
            weth.balanceOf(eve.addr),
            "eve should have received native tokens instead of weth"
        );

        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            1 ether,
            "eve's native balance should have increased by 1 ether"
        );

        assertEq(
            weth.balanceOf(address(wethConverter)) -
                wethConverterWethBalanceBeore,
            1 ether,
            "weth converter's weth balance should have increased by 1 ether"
        );

        assertEq(
            wethConverterNativeBalanceBefore - address(wethConverter).balance,
            1 ether,
            "weth converter's native balance should have decreased by 1 ether"
        );

        assertEq(
            weth.balanceOf(frank.addr),
            frankWethBalanceBefore,
            "frank's weth balance should not have changed"
        );

        assertEq(
            dillonWethBalanceBefore - weth.balanceOf(dillon.addr),
            1 ether,
            "dillon's weth balance should have decreased by 1 ether"
        );

        assertEq(
            erc721s[0].ownerOf(0),
            dillon.addr,
            "dillon should now own token 0"
        );
    }

    function testExecFulfillListingWithCombinedNativeAndWeth() public {
        test(
            this.execFulfillListingWithCombinedNativeAndWethSkip1EthListing,
            context
        );
    }

    function execFulfillListingWithCombinedNativeAndWethSkip1EthListing(
        Context memory
    ) external stateless {
        // eve lists two NFTs, one for 1 ETH and one for 2 ETH
        // she cancels her 1 ETH listing
        // dillon attempts to fulfill both orders with 1.5 WETH and 1.5 ETH
        // dillon should receive the NFT listed for 2 ETH
        // dillon should spend 1.5 ETH and 0.5 WETH
        // dillon should receive 1 WETH back
        // weth converter order should have 1.5 WETH consideration
        // weth converter should have 0.5 WETH more 0.5 ETH less
        // dillon should have 1.5 ETH less 0.5 WETH less
        // eve should have 2 ETH more
        erc721s[0].mint(eve.addr, 0);
        erc721s[0].mint(eve.addr, 1);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// WETH CONVERTER OFFERS NOTHING AND CONSIDERS 1.5 WETH ///
        {
            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(1.5 ether);
            considerationItem = considerationItem.withEndAmount(1.5 ether);
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
            orderParameters = orderParameters.withOffer(new OfferItem[](0));
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[0] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// EVE LISTS NFT #0 FOR 1 ETH ///
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
            considerationItem = considerationItem.withStartAmount(1 ether);
            considerationItem = considerationItem.withEndAmount(1 ether);
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

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                eve.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);

            orders[1] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// EVE LISTS NFT #1 FOR 2 ETH ///
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC721);
            offerItem = offerItem.withToken(address(erc721s[0]));
            offerItem = offerItem.withIdentifierOrCriteria(1);
            offerItem = offerItem.withStartAmount(1);
            offerItem = offerItem.withEndAmount(1);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.NATIVE);
            considerationItem = considerationItem.withToken(address(0));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(2 ether);
            considerationItem = considerationItem.withEndAmount(2 ether);
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

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                eve.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);

            orders[2] = order;
        }

        // Add conditions to weth converter order's extraData
        {
            Condition[] memory conditions = new Condition[](2);

            OrderParameters memory orderParametersOne = orders[1].parameters;
            OrderParameters memory orderParametersTwo = orders[2].parameters;

            // add the other two orders' orderHashes to extraData
            bytes32 orderHashOne = seaport.getOrderHash(
                orderParametersOne.toOrderComponents(0)
            );

            bytes32 orderHashTwo = seaport.getOrderHash(
                orderParametersTwo.toOrderComponents(0)
            );

            conditions[0] = Condition({
                orderHash: orderHashOne,
                amount: orderParametersOne.consideration[0].startAmount,
                startTime: orderParametersOne.startTime,
                endTime: orderParametersOne.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            conditions[1] = Condition({
                orderHash: orderHashTwo,
                amount: orderParametersTwo.consideration[0].startAmount,
                startTime: orderParametersTwo.startTime,
                endTime: orderParametersTwo.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            bytes memory extraData = abi.encodePacked(
                uint8(0),
                abi.encode(conditions)
            );

            orders[0].extraData = extraData;
        }

        // eve cancels her 1 ETH listing
        OrderComponents[] memory oneEthListing = new OrderComponents[](1);
        oneEthListing[0] = orders[1].parameters.toOrderComponents(0);
        vm.prank(eve.addr);
        seaport.cancel(oneEthListing);

        (
            FulfillmentComponent[][] memory offerFulfillmentComponents,
            FulfillmentComponent[][] memory considerationFulfillmentComponents
        ) = fulfill.getAggregatedFulfillmentComponents(orders);

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 eveWethBalanceBefore = weth.balanceOf(eve.addr);

        uint256 dillonNativeBalanceBefore = dillon.addr.balance;

        uint256 dillonWethBalanceBefore = weth.balanceOf(dillon.addr);

        uint256 wethConverterWethBalanceBeore = weth.balanceOf(
            address(wethConverter)
        );

        uint256 wethConverterNativeBalanceBefore = address(wethConverter)
            .balance;

        // dillon attempts to fulfill both listings with 1.5 ETH and 1.5 WETH
        vm.prank(dillon.addr);
        seaport.fulfillAvailableAdvancedOrders{ value: 1.5 ether }(
            orders,
            new CriteriaResolver[](0),
            offerFulfillmentComponents,
            considerationFulfillmentComponents,
            bytes32(0),
            address(0),
            100
        );

        assertEq(
            erc721s[0].ownerOf(0),
            eve.addr,
            "eve should still own token 0"
        );

        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            2 ether,
            "eve should have received 2 ETH"
        );

        assertEq(
            weth.balanceOf(eve.addr) - eveWethBalanceBefore,
            0,
            "eve should not have received any WETH"
        );

        assertEq(
            weth.balanceOf(address(wethConverter)) -
                wethConverterWethBalanceBeore,
            0.5 ether,
            "weth converter's weth balance should have increased by 0.5 WETH"
        );

        assertEq(
            wethConverterNativeBalanceBefore - address(wethConverter).balance,
            0.5 ether,
            "weth converter's native balance should have decreased by 0.5 ETH"
        );

        assertEq(
            dillonWethBalanceBefore - weth.balanceOf(dillon.addr),
            0.5 ether,
            "dillon's weth balance should have decreased by 0.5 WETH"
        );

        assertEq(
            dillonNativeBalanceBefore - dillon.addr.balance,
            1.5 ether,
            "dillon's native balance should have decreased by 1.5 ETH"
        );

        assertEq(
            erc721s[0].ownerOf(1),
            dillon.addr,
            "dillon should now own token 1"
        );
    }

    function testExecFulfillListingWithCombinedNativeAndWethSkip2EthListing()
        public
    {
        test(
            this.execFulfillListingWithCombinedNativeAndWethSkip2EthListing,
            context
        );
    }

    function execFulfillListingWithCombinedNativeAndWethSkip2EthListing(
        Context memory
    ) external stateless {
        // eve lists two NFTs, one for 1 ETH and one for 2 ETH
        // she cancels her 2 ETH listing
        // dillon attempts to fulfill both orders with 1.5 WETH and 1.5 ETH
        // dillon should receive the NFT listed for 1 ETH
        // dillon should spend 1 WETH
        // weth converter order should have 1.5 WETH consideration
        // weth converter should have 1 WETH more 1 ETH less
        // dillon should have 1 WETH less
        // eve should have 1 ETH more
        erc721s[0].mint(eve.addr, 0);
        erc721s[0].mint(eve.addr, 1);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// WETH CONVERTER OFFERS NOTHING AND CONSIDERS 1.5 WETH ///
        {
            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(1.5 ether);
            considerationItem = considerationItem.withEndAmount(1.5 ether);
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
            orderParameters = orderParameters.withConsideration(
                considerationArray
            );
            orderParameters = orderParameters
                .withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);

            orders[0] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// EVE LISTS NFT #0 FOR 1 ETH ///
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
            considerationItem = considerationItem.withStartAmount(1 ether);
            considerationItem = considerationItem.withEndAmount(1 ether);
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

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                eve.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);

            orders[1] = order;
        }

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// EVE LISTS NFT #1 FOR 2 ETH ///
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
            considerationItem = considerationItem.withStartAmount(2 ether);
            considerationItem = considerationItem.withEndAmount(2 ether);
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

            OrderComponents memory orderComponents = orderParameters
                .toOrderComponents(0);

            bytes memory signature = signOrder(
                getSeaport(),
                eve.key,
                getSeaport().getOrderHash(orderComponents)
            );

            order = order.withSignature(signature);

            orders[2] = order;
        }

        // Add conditions to weth converter order's extraData
        {
            Condition[] memory conditions = new Condition[](2);

            OrderParameters memory orderParametersOne = orders[1].parameters;
            OrderParameters memory orderParametersTwo = orders[2].parameters;

            // add the other two orders' orderHashes to extraData
            bytes32 orderHashOne = seaport.getOrderHash(
                orderParametersOne.toOrderComponents(0)
            );

            bytes32 orderHashTwo = seaport.getOrderHash(
                orderParametersTwo.toOrderComponents(0)
            );

            conditions[0] = Condition({
                orderHash: orderHashOne,
                amount: orderParametersOne.consideration[0].startAmount,
                startTime: orderParametersOne.startTime,
                endTime: orderParametersOne.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            conditions[1] = Condition({
                orderHash: orderHashTwo,
                amount: orderParametersTwo.consideration[0].startAmount,
                startTime: orderParametersTwo.startTime,
                endTime: orderParametersTwo.endTime,
                fractionToFulfill: 1,
                totalSize: 1
            });

            bytes memory extraData = abi.encodePacked(
                uint8(0),
                abi.encode(conditions)
            );

            orders[0].extraData = extraData;
        }

        // eve cancels her 1 ETH listing
        OrderComponents[] memory twoEthListing = new OrderComponents[](1);
        twoEthListing[0] = orders[2].parameters.toOrderComponents(0);
        vm.prank(eve.addr);
        seaport.cancel(twoEthListing);

        (
            FulfillmentComponent[][] memory offerFulfillmentComponents,
            FulfillmentComponent[][] memory considerationFulfillmentComponents
        ) = fulfill.getAggregatedFulfillmentComponents(orders);

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 eveWethBalanceBefore = weth.balanceOf(eve.addr);

        uint256 dillonNativeBalanceBefore = dillon.addr.balance;

        uint256 dillonWethBalanceBefore = weth.balanceOf(dillon.addr);

        uint256 wethConverterWethBalanceBeore = weth.balanceOf(
            address(wethConverter)
        );

        uint256 wethConverterNativeBalanceBefore = address(wethConverter)
            .balance;

        // dillon attempts to fulfill both listings with 1.5 ETH and 1.5 WETH
        vm.prank(dillon.addr);
        seaport.fulfillAvailableAdvancedOrders{ value: 1.5 ether }(
            orders,
            new CriteriaResolver[](0),
            offerFulfillmentComponents,
            considerationFulfillmentComponents,
            bytes32(0),
            address(0),
            100
        );

        assertEq(
            erc721s[0].ownerOf(1),
            eve.addr,
            "eve should still own token 1"
        );

        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            1 ether,
            "eve should have received 1 ETH"
        );

        assertEq(
            weth.balanceOf(eve.addr) - eveWethBalanceBefore,
            0,
            "eve should not have received any WETH"
        );

        assertEq(
            wethConverterWethBalanceBeore,
            weth.balanceOf(address(wethConverter)),
            "weth converter's weth balance should have increased by 1 ether"
        );

        assertEq(
            address(wethConverter).balance,
            wethConverterNativeBalanceBefore,
            "weth converter's native balance should have decreased by 1 ether"
        );

        assertEq(
            dillonWethBalanceBefore,
            weth.balanceOf(dillon.addr),
            "dillon's weth balance should be unchanged"
        );

        assertEq(
            dillonNativeBalanceBefore - dillon.addr.balance,
            1 ether,
            "dillon's native balance should decrease by 1 ether"
        );

        assertEq(
            erc721s[0].ownerOf(0),
            dillon.addr,
            "dillon should now own token 0"
        );
    }

    function testExecRebalance() public {
        test(this.execRebalance, context);
    }

    function execRebalance(Context memory) external stateless {
        // weth converter has 500 WETH and 500 ETH
        // dillon offers 600 WETH for eve's NFT
        // weth converter offers 600 ETH and considers 600 WETH
        // eve accepts dillon's offer and receives 600 ETH
        // weth converter should unwrap 100 WETH to 100 ETH
        // weth converter should receive 600 WETH
        // weth converter should have 0 ETH and 1000 WETH
        erc721s[0].mint(eve.addr, 0);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 600 WETH FOR EVE'S NFT
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(600 ether);
            offerItem = offerItem.withEndAmount(600 ether);

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
            offerItem = offerItem.withStartAmount(600 ether);
            offerItem = offerItem.withEndAmount(600 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(600 ether);
            considerationItem = considerationItem.withEndAmount(600 ether);
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

        /// EVE ACCEPTS OFFER AND RECEIVES 600 ETH
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
            considerationItem = considerationItem.withStartAmount(600 ether);
            considerationItem = considerationItem.withEndAmount(600 ether);
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

        uint256 wethConverterWethBalanceBefore = weth.balanceOf(
            address(wethConverter)
        );

        uint256 wethConverterNativeBalanceBefore = address(wethConverter)
            .balance;
        assertEq(
            wethConverterWethBalanceBefore,
            500 ether,
            "weth converter weth balance should be 500 weth"
        );
        assertEq(
            wethConverterNativeBalanceBefore,
            500 ether,
            "weth converter native balance should be 500 ether"
        );

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 dillonWethBalanceBefore = weth.balanceOf(dillon.addr);

        seaport.matchAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        assertEq(erc721s[0].ownerOf(0), dillon.addr, "dillon should own nft");
        assertEq(
            dillonWethBalanceBefore - weth.balanceOf(dillon.addr),
            600 ether,
            "dillon should have 600 weth less"
        );
        assertEq(
            weth.balanceOf(address(wethConverter)),
            600 ether,
            "weth converter weth balance should be 600 weth"
        );
        assertEq(
            address(wethConverter).balance,
            400 ether,
            "weth converter native balance should be 400 ether"
        );
        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            600 ether,
            "eve's native balance should have increased by 600 ether"
        );
    }

    function testExecUnwrapIfNecessary() public {
        test(this.execUnwrapIfNecessary, context);
    }

    function execUnwrapIfNecessary(Context memory) external stateless {
        // weth converter starts with 900 weth and 100 eth
        // dillon offers 200 weth for eve's nft
        // eve accepts offer
        // weth converter doesn't have enough native balance so it unwraps weth
        // weth converter targets 50/50 split after order fulfillment
        // so it will unwrap (900 weth + 100 eth + 200 weth) / 2 = 600 weth
        // weth converter will have 300 weth and 700 eth before order fulfillment
        // weth converter offers 200 eth and considers 200 weth
        // weth converter will have 500 weth and 500 eth after order fulfillment

        // set up test so weth converter has 900 weth and 100 eth
        vm.prank(address(wethConverter));
        weth.deposit{ value: 400 ether }();

        assertEq(
            address(wethConverter).balance,
            100 ether,
            "weth converter native balance should be 100 ether"
        );
        assertEq(
            weth.balanceOf(address(wethConverter)),
            900 ether,
            "weth converter weth balance should be 500 weth"
        );

        erc721s[0].mint(eve.addr, 0);

        ConsiderationItem[] memory considerationArray = new ConsiderationItem[](
            1
        );
        OfferItem[] memory offerArray = new OfferItem[](1);
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        OrderParameters memory orderParameters;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        /// DILLON OFFERS 200 WETH FOR EVE'S NFT
        {
            OfferItem memory offerItem = OfferItemLib.empty();
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(wethAddress);
            offerItem = offerItem.withIdentifierOrCriteria(0);
            offerItem = offerItem.withStartAmount(200 ether);
            offerItem = offerItem.withEndAmount(200 ether);

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
            offerItem = offerItem.withStartAmount(200 ether);
            offerItem = offerItem.withEndAmount(200 ether);

            offerArray[0] = offerItem;

            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .empty();
            considerationItem = considerationItem.withItemType(ItemType.ERC20);
            considerationItem = considerationItem.withToken(wethAddress);
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem = considerationItem.withStartAmount(200 ether);
            considerationItem = considerationItem.withEndAmount(200 ether);
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

        /// EVE ACCEPTS OFFER AND RECEIVES 200 ETH
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
            considerationItem = considerationItem.withStartAmount(200 ether);
            considerationItem = considerationItem.withEndAmount(200 ether);
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

        uint256 eveNativeBalanceBefore = eve.addr.balance;

        uint256 dillonWethBalanceBefore = weth.balanceOf(dillon.addr);

        seaport.matchAdvancedOrders(
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        assertEq(erc721s[0].ownerOf(0), dillon.addr, "dillon should own nft");
        assertEq(
            dillonWethBalanceBefore - weth.balanceOf(dillon.addr),
            200 ether,
            "dillon should have 200 weth less"
        );
        assertEq(
            weth.balanceOf(address(wethConverter)),
            500 ether,
            "weth converter weth balance should be 500 weth"
        );
        assertEq(
            address(wethConverter).balance,
            500 ether,
            "weth converter native balance should be 500 ether"
        );
        assertEq(
            eve.addr.balance - eveNativeBalanceBefore,
            200 ether,
            "eve's native balance should have increased by 200 ether"
        );
    }
}
