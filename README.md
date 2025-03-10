<center>
<img src="./logo/logo.png" width="200"/>
</center>


## SlotMachine Smart Contract

The smart contract powers casino games on Superchain, ensuring fairness and transparency. It handles USDC bets, payouts, and game logic securely on-chain.

## Config env file
PRIVATE_KEY=
GUARDIAN_ADDRESS=
ADMIN_ADDRESS=

## Deploy Smart Contract
```
npx hardhat run --network [network name] run scripts/deploySlotMachine
```

## Verify Smart Contract
```
npx hardhat verify --network [network name] [contract address] --constructor-args scripts/arguments.js
```