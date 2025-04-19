# CryptoLegacy – Secure On-Chain Inheritance & Recovery

**CryptoLegacy** is a modular, EIP-2535 Diamond-based smart contract system built using **Foundry**. It enables decentralized **inheritance**, **asset recovery**, and **estate planning** for crypto users, ensuring privacy, flexibility, and cross-chain support.

---

## Key Features

**Secure Self-Custody & Inheritance**  
- Assets stay in your own wallets, never locked by third parties.  
- Automatically distribute crypto to beneficiaries after defined timeouts or emergencies.

**Privacy by Design**  
- Beneficiary info remains hashed until needed.  
- Conceals asset balances to prevent coercion or internal disputes.

**Security & Recovery**  
- Flexible “Trusted Guardians” or multi-sig “Recovery” roles confirm inactivity without direct asset control.  
- Hidden recovery addresses let you reclaim funds if keys are lost or compromised.

**Flexible for Rapidly Changing Investments**  
- Quickly adapt to new protocols, NFTs, staking, or sidechains.  
- Update beneficiaries, wallets, or logic without replacing the entire system.

**Automated Distribution & Minimal Coordination**  
- Timeouts and challenge periods remove human error and reduce stress.  
- Beneficiaries claim assets through clearly defined, on-chain rules.

**Reliability & Fail-Safe Execution**  
- Eliminates legal complexity, third-party mistakes, or indefinite asset lock-ups.  
- Automated transfers ensure your plan executes exactly as intended.

**Simplicity with Advanced Options**  
- Default flow is straightforward, yet advanced users can activate guardians, multi-sig recovery, or extra distribution rules.  
- No complicated legal documents required.

**Borderless & Jurisdiction-Free**  
- Operates fully on-chain with no reliance on local regulations.  
- Transfers execute smoothly regardless of geographic or legal boundaries.

**Transparent, Predictable Costs**  
- Pay small periodic fees or opt for a one-time NFT pass.  
- Avoid the hidden expenses and headaches of traditional legal processes.

**Cross-Chain Integration**  
- Seamlessly move lifetime NFTs and referral codes between EVM-compatible networks.  
- Grow your inheritance strategy across multiple chains without extra hassle.

**Modular Plugin Architecture**  
- Use DAO-approved plugins for NFTs, guardians, custom distributions, or DeFi integrations.  
- Add, remove, or update features anytime—staying future-proof and secure.

**Lifetime NFT Pass**  
- One-time purchase covers unlimited updates on all supported chains.  
- Also grants voting power and potential airdrop benefits in the DAO.

**DAO Governance & Path to Decentralization**  
- NFT holders shape platform decisions through on-chain voting.  
- Long-term plan to evolve into a fully open-source, community-driven protocol.

**Security-First Engineering**  
- Extensive audits, bug bounties, and minimized on-chain storage.  
- Personal contracts keep assets safe in your wallets until needed.

**Enhanced On-Chain Privacy**  
- Encrypts sensitive information so it’s unreadable until distribution.  
- Future zero-knowledge plugins can hide wallet interactions entirely.

**Protocol Integrations**  
- Beneficiaries can easily stake, swap, borrow, or manage DeFi positions.  
- Flexible expansions enable new features without contract redeployments.

**Clear, Detailed Contract Flow**  
- Step-by-step setups for beneficiaries, guardians, and recovery roles.  
- Ensures distributions happen smoothly, with no confusion or disputes.

---

**CryptoLegacy** – because your crypto legacy deserves **security**, **privacy**, and **peace of mind**.

---

## Contracts Overview

| Contract                             | Description                                                                                                                                                    |
|--------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CryptoLegacy**                     | Core EIP-2535 Diamond contract for inheritance logic and plugin management. Holds no assets directly.                                                          |
| **CryptoLegacyBuildManager**         | Manages creation and configuration of CryptoLegacy instances, including fees and cross-chain logic.                                                            |
| **BeneficiaryRegistry**              | Maintains mappings between beneficiary hashes and CryptoLegacy contract addresses.                                                                             |
| **LegacyMessenger**                  | Forwards on-chain messages and logs message block numbers.                                                                                                     |
| **FeeRegistry**                      | Manages fees (build, update, NFT passes) with support for discounts and referral commissions.                                                                  |
| **PluginsRegistry**                  | Whitelists approved plugin (facet) contracts to secure Diamond upgrades.                                                                                       |
| **LifetimeNft**                      | ERC-721 NFT granting lifetime usage rights, eliminating recurring fees; supports cross-chain transfers.                                                        |
| **CryptoLegacyBasePlugin**           | Default facet implementing primary inheritance logic (distribution schedules, inactivity checks).                                                               |
| **NftLegacyPlugin**                  | Plugin supporting inheritance of NFTs with specific beneficiaries and claim processes.                                                                         |
| **BeneficiaryPluginAddRights**       | Allows beneficiaries to add or propose additional plugin logic post-activation.                                                                                |
| **TrustedGuardiansPlugin**           | Lets a specified set of guardians vote to start or expedite distribution if the owner is inactive.                                                             |
| **LegacyRecoveryPlugin**             | Handles additional multi-sig or “Recovery” roles that can move tokens or override distribution logic in certain emergency scenarios.                           |
| **UpdateRolePlugin**                 | Allows designated roles (beyond the owner) to trigger periodic contract updates.                                                                               |
| **SignatureRoleTimelock**            | Role-based function signature timelock for admin-level operations — enables scheduled calls with a safe waiting period.                                          |
| **LockChainGate**                    | Facilitates cross-chain locking/unlocking of the Lifetime NFT for fee-free usage across multiple networks.                                                     |
| **MultiPermit**                      | Enables batch ERC-20 permit approvals to streamline transfers.                                                                                                 |
| **ProxyBuilder** & **ProxyBuilderAdmin** | Deploy and manage TransparentUpgradeableProxy setups for certain auxiliary components.                                                                        |

---

## Getting Started (Foundry)

1. **Clone and install dependencies**:

```bash
git clone --recurse-submodules -j8 https://github.com/CryptoCust/cryptolegacy-contracts.git
cd cryptolegacy-contracts
foundryup
```

2. **Compile contracts:**
```bash
npm run build
```

3. **Run tests:**
```bash
npm test
```

---

## Coverage (Foundry)

1. **Install lcov dependency**:  
   **Windows or Ubuntu**:
   ```bash
   sudo apt-get install lcov
   ```
   **macOS**:
   ```bash
   brew install lcov
   ```

2. **Run coverage summary:**
```bash
npm run coverage-summary
```

3. **Run coverage HTML generating:**
```bash
npm run coverage-html
```

---

## Additional Documentation

For advanced usage, detailed workflows, or plugin development guides, visit the [CryptoLegacy Docs](https://docs.cryptolegacy.app/).

---

## Security

**Diamond Standard (EIP-2535)**  
- The core contracts implement a **diamond architecture** (`LibDiamond`, `DiamondLoupeFacet`, `IDiamondCut`, etc.). This modular design allows **secure, upgradeable** facets (plugins) while avoiding a single upgrade point of failure.

**Reentrancy Protections**  
- Multiple contracts use [OpenZeppelin’s **ReentrancyGuard**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol).  
- Functions like `beneficiaryClaim`, `transferNftTokensToLegacy`, and `updateByUpdater` are guarded by `nonReentrant`, preventing typical reentrancy exploits.

**Checks–Effects–Interactions**  
- The code enforces thorough checks (e.g. `_checkDistributionReady()` or `_checkSenderOwner()`) before mutating state or transferring tokens.  
- External calls (like `transferFrom` or `safeTransferFrom`) happen only after conditions and internal state updates are validated.

**Minimal On-Chain Storage**  
- User assets remain in user wallets until distribution triggers (`transferFrom` calls move tokens at the last stage).  
- Beneficiary addresses are stored **hashed** (`keccak256`), minimizing sensitive on-chain data.

**Access Controls & Ownership**  
- Ownership checks (`_checkOwner()`, `_checkSenderOwner()`) ensure only valid addresses can perform high-level actions.  
- Build managers are validated via `_checkBuildManagerValid()`, preventing unauthorized contract creation or updates.  
- The contract can be **paused** or **unpaused** (`LibDiamond.setPause`), adding another layer of security when needed.

**Plugins Whitelist**  
- New facets (plugins) must be **registered** in `PluginsRegistry` and pass DAO/security reviews.  
- The system rejects unregistered or malicious plugins, keeping the diamond contract safe from unsafe code injection.

**EnumerableSet for Secure Tracking**  
- [OpenZeppelin’s **EnumerableSet**](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol) is used to manage lists (e.g., `updaters`, `beneficiaries`, `guardians`) without the pitfalls of manual array handling.

Overall, this architecture and code design prioritize **robust upgradeability**, **reentrancy protection**, **reduced on-chain risk**, and **clear role-based access** — ensuring a reliable and secure CryptoLegacy system.

---

## Legal Disclaimer

> **© 2025 CryptoCustoms. All rights reserved.**

This repository and its contents — including all smart contracts, documentation, and code samples — are the proprietary intellectual property of the CryptoCustoms team and are protected under international copyright laws.

- **No License Granted:** This codebase is **not open source**. It is provided strictly for review, research, and evaluation. No permission is granted to use, deploy, copy, modify, or distribute this code or its derivatives without prior written approval from CryptoCustoms.

- **DAO Governance & Licensing Roadmap:**  
  The CryptoLegacy protocol is supported by an active DAO composed of Lifetime NFT holders who may vote on key platform decisions. While DAO input is essential, any transition to an open-source license or public-use model **requires explicit team approval and a formal DAO vote**. Until such an event occurs and is ratified through legal documentation, all rights remain fully reserved by the CryptoCustoms team.

- **No Legal or Financial Advice:** This code and its related materials do **not constitute legal, financial, or investment advice**. Always consult professional advisors for guidance relevant to your situation.

- **No Warranty or Liability:** All content is provided “as is” with no guarantees or warranties. CryptoCustoms and its contributors accept **no liability** for any loss, damage, or misuse arising from interaction with this software or its derivatives.

- **Compliance Responsibility:** It is your sole responsibility to ensure that any use, adaptation, or integration of this system complies with the laws and regulations of your jurisdiction — especially those related to digital assets, inheritance, and data privacy.

For licensing requests, audit coordination, or strategic partnerships, contact: [cryptocust@proton.me](mailto:cryptocust@proton.me)

---

## License

Proprietary license, with intent to open-source in the future. See `LICENSE` file for details.

**CryptoLegacy** – Because your crypto legacy deserves security, privacy, and flexibility — no matter what happens.

© 2025 CryptoCustoms. All rights reserved.