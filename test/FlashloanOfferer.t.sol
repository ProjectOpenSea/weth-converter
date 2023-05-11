// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {GenericAdapterInterface} from "../src/interfaces/GenericAdapterInterface.sol";

import {FlashloanOffererInterface} from "../src/interfaces/FlashloanOffererInterface.sol";

import {GenericAdapter} from "../src/optimized/GenericAdapter.sol";

import {ReferenceGenericAdapter} from "../src/reference/ReferenceGenericAdapter.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

contract GenericAdapterTest is BaseOrderTest {
    struct Context {
        FlashloanOffererInterface flashloanOfferer;
        bool isReference;
    }

    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    function setUp() public override {
        super.setUp();

        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode("out/FlashloanOfferer.sol/FlashloanOfferer.json", abi.encode(address(consideration)))
        );

        testFlashloanOffererReference = FlashloanOffererInterface(
            deployCode(
                "out/ReferenceFlashloanOfferer.sol/ReferenceFlashloanOfferer.json", abi.encode(address(consideration))
            )
        );

        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();
    }

    function test(function(Context memory) external fn, Context memory context) internal {
        try fn(context) {
            fail("Stateless test function should have reverted with assertion failure status.");
        } catch (bytes memory reason) {
            assertPass(reason);
        }
    }

    function testFlashloanOffererReceive() public {
        test(this.execReceive, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execReceive, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execReceive(Context memory context) external stateless {
        (bool success,) = address(context.flashloanOfferer).call{value: 1 ether}("");
        require(success);
        assertEq(address(context.flashloanOfferer).balance, 1 ether);

        testERC1155.mint(address(context.flashloanOfferer), 1, 1);
        testERC721.mint(address(this), 2);
        testERC721.safeTransferFrom(address(this), address(context.flashloanOfferer), 2);
    }

    function testSupportsInterface() public {
        test(this.execSupportsInterface, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execSupportsInterface, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(context.flashloanOfferer.supportsInterface(type(ContractOffererInterface).interfaceId), true);
    }

    function testGetSeaportMetadata() public {
        test(this.execGetSeaportMetadata, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execGetSeaportMetadata, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execGetSeaportMetadata(Context memory context) external stateless {
        (string memory name, Schema[] memory schemas) = context.flashloanOfferer.getSeaportMetadata();
        assertEq(name, "FlashloanOfferer");
        assertEq(schemas.length, 0);
    }
}
