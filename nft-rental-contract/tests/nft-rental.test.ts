import { describe, it, expect } from "vitest";
import { Cl } from "@stacks/transactions";

// The `simnet` object is provided globally by vitest-environment-clarinet.

describe("NFT Rental Contract", () => {
  it("allows minting, listing, renting and checks can-use?", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer")!;
    const lender = accounts.get("wallet_1")!;
    const renter = accounts.get("wallet_2")!;

    // 1. Mint a game asset NFT to the lender.
    const mintCall = simnet.callPublicFn(
      "nft-rental",
      "mint",
      [Cl.principal(lender.address)],
      deployer
    );
    expect(mintCall.result).toBeOk(Cl.uint(1));

    // 2. Lender lists the NFT for rent.
    const listCall = simnet.callPublicFn(
      "nft-rental",
      "list-for-rent",
      [Cl.uint(1), Cl.uint(10), Cl.uint(100)], // 10 STX per block, up to 100 blocks
      lender
    );
    expect(listCall.result).toBeOk(Cl.bool(true));

    // 3. Renter rents the NFT.
    const rentCall = simnet.callPublicFn(
      "nft-rental",
      "rent",
      [Cl.uint(1), Cl.uint(10)],
      renter
    );
    expect(rentCall.result).toBeOk(Cl.bool(true));

    // 4. Both lender and renter should have temporary usage rights.
    const lenderCanUse = simnet.callReadOnlyFn(
      "nft-rental",
      "can-use?",
      [Cl.principal(lender.address), Cl.uint(1)],
      lender
    );
    expect(lenderCanUse.result).toBeOk(Cl.bool(true));

    const renterCanUse = simnet.callReadOnlyFn(
      "nft-rental",
      "can-use?",
      [Cl.principal(renter.address), Cl.uint(1)],
      renter
    );
    expect(renterCanUse.result).toBeOk(Cl.bool(true));
  });

  it("lets owner cancel a listing when not rented", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer")!;
    const lender = accounts.get("wallet_1")!;

    const mintCall = simnet.callPublicFn(
      "nft-rental",
      "mint",
      [Cl.principal(lender.address)],
      deployer
    );
    expect(mintCall.result).toBeOk(Cl.uint(1));

    const listCall = simnet.callPublicFn(
      "nft-rental",
      "list-for-rent",
      [Cl.uint(1), Cl.uint(5), Cl.uint(50)],
      lender
    );
    expect(listCall.result).toBeOk(Cl.bool(true));

    const cancelCall = simnet.callPublicFn(
      "nft-rental",
      "cancel-listing",
      [Cl.uint(1)],
      lender
    );
    expect(cancelCall.result).toBeOk(Cl.bool(true));
  });
});
