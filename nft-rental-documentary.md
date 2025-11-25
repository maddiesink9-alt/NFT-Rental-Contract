# NFT Rental Contract – 5 Minute Documentary Script

## 0:00 – Problem & Vision
Gaming and metaverse projects often want to give players **temporary access** to premium NFTs – think rented skins, weapons, or land – without ever giving up long‑term ownership.

Today, most projects hack this by either:
- Transferring the NFT to the renter, which is risky and confusing, or
- Building off‑chain rental logic that the game server enforces manually.

The goal of this project is to keep ownership **on‑chain and permanent**, but still let another player use the asset for a limited time. That is exactly what the **NFT Rental Contract** provides.

## 0:45 – High‑Level Design
This project has three main pieces:
1. A **Clarity smart contract** called `nft-rental` that mints game assets and manages rental listings.
2. A **Clarinet test suite** that proves core flows: mint → list → rent → check access.
3. A small **front‑end UI** (`ui/index.html`) that shows how a game or metaverse client would call these functions.

The key idea: the contract never transfers ownership to the renter. Instead, it tracks who is allowed to "use" an NFT at a given time, and exposes a single read‑only function: `can-use?`.

## 1:30 – Smart Contract Walkthrough
The contract lives in `contracts/nft-rental.clar`.

Data model:
- `game-asset` – a simple non‑fungible token representing in‑game items.
- `nft-owners` – maps `token-id` → long‑term owner principal.
- `rental-listings` – maps `token-id` → rental terms (price per block, max duration, lender).
- `active-rentals` – maps `token-id` → current renter and `expires-at` block.

Core public functions:
- `mint(recipient)` – only the deployer can mint new NFTs. The token is recorded in `nft-owners` and minted via `define-non-fungible-token`.
- `list-for-rent(token-id, price-per-block, max-duration)` – lets the owner list their NFT. The token must not currently be rented.
- `rent(token-id, duration)` – a player starts a rental. The function:
  - Checks duration against `max-duration`.
  - Transfers STX from renter to lender using `stx-transfer?`.
  - Records the renter and `expires-at = block-height + duration` in `active-rentals`.
- `cancel-listing(token-id)` – owner can remove a listing when there is no active rental.
- `end-rental-early(token-id)` – owner or renter can close a rental before expiry (with no refunds in this simple version).

The most important read‑only function:
- `can-use?(user, token-id)` – returns `true` if and only if:
  - the user is the owner and the token exists, or
  - there is an active rental that has not expired and the user is either the owner or the renter.

This is what game logic should call instead of checking NFT ownership directly.

## 3:00 – Tests with Clarinet
In `tests/nft-rental.test.ts` we use **vitest-environment-clarinet** and the global `simnet` helper.

The tests cover:
1. **Mint → List → Rent → Access**
   - Deployer mints a game asset to `wallet_1`.
   - `wallet_1` lists token `1` for rent at a fixed price per block.
   - `wallet_2` calls `rent` for a chosen duration.
   - We then call `can-use?` for both lender and renter and assert they both receive `ok true`.

2. **Cancel Listing**
   - Mint and list a token.
   - Owner calls `cancel-listing` and we assert the call returns `ok true`.

This gives you a repeatable on‑chain story that you can run with `npm test` via Clarinet.

## 4:00 – UI & Player Flow
The UI lives in `ui/index.html`. It is intentionally lightweight so it can be read and demoed quickly.

Panels:
- **Step 1 – Configure Contract**
  - Paste the deployed contract address and confirm the contract name (`nft-rental`).
- **Step 2 – Creator Flow**
  - Mint an NFT to the creator / lender.
  - List a token with a price per block and max duration.
- **Step 3 – Player Flow**
  - A player enters the token id and desired duration and clicks **Rent NFT**.
  - Anyone can call **Check can-use?** to see if a given principal currently has access.
- **Event Log**
  - Every button click logs a simulated contract call, including function name and arguments. In a production dApp, this is where you plug in `@stacks/transactions` + wallet integration.

The redesign aspect is about UX: grouping actions into a clear three‑step timeline (setup → creator → player) and adding an event log so you can narrate what is happening on‑chain in real time.

## 4:45 – How to Use This in a Demo
For a live 5‑minute presentation you can:
1. Spend ~1 minute on the problem: why NFT rentals matter for games and metaverse.
2. Spend ~2 minutes walking through the contract concepts and `can-use?`.
3. Spend ~1 minute showing tests running in Clarinet.
4. Spend the final minute clicking through the UI panels and explaining how a real wallet integration would wire into these buttons.

That combination gives you a complete story: **on‑chain logic, tested flows, and a concrete UX for temporary NFT access without transferring ownership.**
