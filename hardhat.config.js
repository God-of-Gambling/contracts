require('dotenv').config();
require('@nomicfoundation/hardhat-ethers');
require("@nomicfoundation/hardhat-verify");

const PRIVATE_KEY = process.env.PRIVATE_KEY

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
  defaultNetwork: 'hardhat',
  networks: { 
    'hardhat': {      
      chainId: 1337     
    },
    'monad-testnet': {
      url: 'https://testnet-rpc.monad.xyz',
      chainId: 10143,
      accounts: [PRIVATE_KEY],
      timeout: 120000,
      allowUnlimitedContractSize: true,
    },
    // 'ink': {
    //   url: 'https://rpc-gel.inkonchain.com',
    //   chainId: 57073,
    //   accounts: [PRIVATE_KEY],
    //   allowUnlimitedContractSize: true,
    // },
    'superseed-sepolia': {
      url: 'https://sepolia.superseed.xyz',
      chainId: 53302,
      accounts: [PRIVATE_KEY],
      allowUnlimitedContractSize: true
    },
    'soneium-minato': {
      url: 'https://rpc.minato.soneium.org',
      chainId: 1946,
      accounts: [PRIVATE_KEY],
      allowUnlimitedContractSize: true
    }
  },
  etherscan: {
    enabled: true,
    apiKey: {
      'soneium-minato': '7a04062b-373e-47a7-b52e-6bd9d484a33b',
      'superseed-sepolia': ''
    },
    customChains: [
      {
        network: "superseed-sepolia",
        chainId: 53302,
        urls: {
          apiURL: "https://explorer-sepolia-superseed-826s35710w.t.conduit.xyz/api",
          browserURL: "https://explorer-sepolia-superseed-826s35710w.t.conduit.xyz:443"
        }
      },
      {
        network: "soneium-minato",
        chainId: 1946,
        urls: {
          apiURL: "https://soneium-minato.blockscout.com/api",
          browserURL: "https://soneium-minato.blockscout.com"
        }
      }
    ]
  },
  sourcify: {
    enabled: false,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://testnet.monadexplorer.com"
  },
  paths: {
    sources: "./contracts",
    cache: "./cache",
    artifacts: "./artifacts"
  },
};
