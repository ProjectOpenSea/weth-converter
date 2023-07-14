# WETH Converter

WETH Converter is a Seaport app that offers ETH in exchange for an equal amount of WETH, or vice versa. It relies on [the contract order pattern](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#contract-orders) that was added as part of Seaport v1.2.

The contract has been deployed to [`0x000000000aDac1dE790E7C635887cFA7C40c161d`.](https://etherscan.io/address/0x000000000adac1de790e7c635887cfa7c40c161d#code)

## Install

To install dependencies and compile contracts:

```bash
git clone --recurse-submodules https://github.com/ProjectOpenSea/weth-converter && cd weth-converter && forge build
```

## Tests

To run tests:

```bash
forge test
```

## License

[MIT](LICENSE) Copyright 2023 Ozone Networks, Inc.
