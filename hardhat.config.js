require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();
const { REPORT_GAS, PRIVATE_KEY, API_KEY } = process.env;

module.exports = {
    solidity: {
        version: "0.8.19",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    networks: {
        hardhat: {
            forking: {
                url: "https://rpc.ankr.com/eth",
                blockNumber: 17982470
            }
        },
        base_goerli: {
            url: "https://rpc.ankr.com/base_goerli",
            accounts: [PRIVATE_KEY]
        }
    },
    gasReporter: {
        enabled: REPORT_GAS === "true" ? true : false,
        currency: "USD"
    },
    etherscan: {
        apiKey: API_KEY
    }
};
