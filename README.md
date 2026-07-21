# GojiSwap

Front-end (and related assets) for **GojiSwap** — a React dApp-style swap UI, with a Solidity farming contract at the repo root.

## What this repo contains

- **`GojiSwap-main/`** — Create React App project
  - React 17 + Redux + React Router
  - Web3 / Web3Modal for wallet connection
  - Bootstrap / Material UI styling and static assets
- **`Farming.sol`** — Solidity farming contract (root level)

## Stack

- React, Redux, Sass
- `web3`, `web3modal`
- Solidity (`Farming.sol`)

## Run the UI locally

```bash
cd GojiSwap-main
npm install
npm start
```

## Notes

- UI and contract configuration (RPC URLs, contract addresses) must be set for your target network.
- This is historical project work; dependencies are from ~2021 and may need updates for modern Node versions.

## Author

[ArmaghanRazaChaudhary](https://github.com/ArmaghanRazaChaudhary)
