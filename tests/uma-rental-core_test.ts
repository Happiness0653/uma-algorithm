import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Uma Rental Protocol: Property Registration",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const block = chain.mineBlock([
      Tx.contractCall('uma-rental-core', 'register-property', [
        types.utf8('Luxury Downtown Apartment'),
        types.utf8('Modern 2BR with city view'),
        types.uint(2000000), // 2000 STX per month
        types.uint(4000000)  // 4000 STX security deposit
      ], deployer.address)
    ]);

    // Assert property registration succeeded
    assertEquals(block.height, 2);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "Uma Rental Protocol: Create Agreement",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const tenant = accounts.get('wallet_1')!;
    
    // First register a property
    const registerBlock = chain.mineBlock([
      Tx.contractCall('uma-rental-core', 'register-property', [
        types.utf8('City Center Studio'),
        types.utf8('Compact living space in prime location'),
        types.uint(1500000), // 1500 STX per month
        types.uint(3000000)  // 3000 STX security deposit
      ], deployer.address)
    ]);

    // Then create an agreement
    const agreementBlock = chain.mineBlock([
      Tx.contractCall('uma-rental-core', 'create-agreement', [
        types.uint(1),        // property-id
        types.uint(100),       // start block
        types.uint(1000)       // end block
      ], tenant.address)
    ]);

    // Assert agreement creation succeeded
    assertEquals(agreementBlock.height, 3);
    agreementBlock.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "Uma Rental Protocol: Monthly Rent Payment",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const tenant = accounts.get('wallet_1')!;
    
    // Setup: register property and create agreement
    const setupBlocks = chain.mineBlock([
      Tx.contractCall('uma-rental-core', 'register-property', [
        types.utf8('Suburban Family Home'),
        types.utf8('Spacious 3BR house'),
        types.uint(3000000), // 3000 STX per month
        types.uint(6000000)  // 6000 STX security deposit
      ], deployer.address),
      Tx.contractCall('uma-rental-core', 'create-agreement', [
        types.uint(1),        // property-id
        types.uint(100),       // start block
        types.uint(1000)       // end block
      ], tenant.address)
    ]);

    // Simulate rent payment
    const paymentBlock = chain.mineBlock([
      Tx.contractCall('uma-rental-core', 'pay-monthly-rent', [
        types.uint(1)  // agreement-id
      ], tenant.address)
    ]);

    // Assert payment succeeded
    assertEquals(paymentBlock.height, 3);
    paymentBlock.receipts[0].result.expectOk().expectBool(true);
  }
});