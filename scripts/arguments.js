const { ethers, network } = require('hardhat');
const currencies = require('./currencies');

const maxBet = '1'
const minBet = '0.1'

const guardianAddress = process.env.GUARDIAN_ADDRESS || '';
const adminAddress = process.env.ADMIN_ADDRESS || '';

const networkId = network.config.chainId;

if (!currencies[networkId]) {
    throw new Error(`Unsupported network ID: ${networkId}`);
}

const currency = currencies[networkId]

module.exports = [
    guardianAddress,
    adminAddress,
    currency.address,
    ethers.parseUnits(minBet, currency.decimals),
    ethers.parseUnits(maxBet, currency.decimals)
];