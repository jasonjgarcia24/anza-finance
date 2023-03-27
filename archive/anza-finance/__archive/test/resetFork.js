require("dotenv").config();
const { network } = require("hardhat");
const { BLOCK_NUMBER } = require("../config");

async function reset() {
    await network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: process.env.ALCHEMY_MAINNET_URL,
                    blockNumber: BLOCK_NUMBER
                },
            },
        ],
    });
};

module.exports.reset = reset;