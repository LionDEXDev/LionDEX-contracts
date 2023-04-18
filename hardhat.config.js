require('@nomiclabs/hardhat-waffle');
require('@nomiclabs/hardhat-etherscan');
require('hardhat-contract-sizer');
require('@typechain/hardhat');

const {
  ARBITRUM_MAINNET_URL,
  ARBITRUM_TESTNET_DEPLOY_KEY,
  ARBITRUM_MAINNET_DEPLOY_KEY,
  ARBITRUM_ONE_APIKEY,
  ARBITRUM_MAINNET_TEST_DEPLOY_KEY,
  // ARBITRUM_TESTNET_URL,
  // ARBITRUM_DEPLOY_KEY,
  ARBITRUM_URL,
  AVAX_DEPLOY_KEY,
  AVAX_URL
 } = require("./env.json");


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.info(account.address);
  }
});

const accounts = [
];

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      forking: {
        url: 'https://rpc.ankr.com/arbitrum',
        accounts: accounts,
        blockNumber: 45976671,
      },
      allowUnlimitedContractSize: true,
    },
    arbitrumTestnet: {
      url: 'https://goerli-rollup.arbitrum.io/rpc',
      chainId: 421613,
      accounts: [ARBITRUM_TESTNET_DEPLOY_KEY],
    }, //
    arbitrumTestnet1: {
      url: 'https://endpoints.omniatech.io/v1/arbitrum/goerli/public',
      chainId: 421613,
      accounts: [ARBITRUM_TESTNET_DEPLOY_KEY],
    },
    arbitrumMainNet: {
      url: ARBITRUM_MAINNET_URL,
      chainId: 42161,
      accounts: [ARBITRUM_MAINNET_DEPLOY_KEY],
    },
    arbitrumMainNetTest: {
      url: ARBITRUM_MAINNET_URL,
      chainId: 42161,
      accounts: [ARBITRUM_MAINNET_TEST_DEPLOY_KEY],
    },
    // avax: {
    //   url: AVAX_URL,
    //   gasPrice: 200000000000,
    //   chainId: 43114,
    //   accounts: [AVAX_DEPLOY_KEY],
    // },
    //   polygon: {
    //     url: POLYGON_URL,
    //     gasPrice: 100000000000,
    //     chainId: 137,
    //     accounts: [POLYGON_DEPLOY_KEY]
    //   },
    //   mainnet: {
    //     url: MAINNET_URL,
    //     gasPrice: 50000000000,
    //     accounts: [MAINNET_DEPLOY_KEY]
    //   }
    // },
    //   etherscan: {
    //     apiKey: {
    //       mainnet: MAINNET_DEPLOY_KEY,
    //       arbitrumOne: ARBISCAN_API_KEY,
    //       avalanche: SNOWTRACE_API_KEY,
    //       bsc: BSCSCAN_API_KEY,
    //       polygon: POLYGONSCAN_API_KEY,
    //     }
  },
  etherscan: {
    apiKey: {
      arbitrumOne: ARBITRUM_ONE_APIKEY,
    },
  },
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};
