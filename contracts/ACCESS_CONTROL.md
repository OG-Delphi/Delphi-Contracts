# Access Control Documentation

## Overview

This protocol implements minimal, production-ready access control designed for decentralized autonomous operation with optional DAO governance. The architecture follows a "trust-minimized" approach where core trading and settlement logic is immutable, while governance functions are controlled by an owner (deployer → DAO).

## Security Model

### Design Philosophy

1. **Immutable Core Logic**: Trading, settlement, and redemption cannot be controlled by admins
2. **Minimal Governance**: Only configuration parameters can be adjusted by governance
3. **DAO-Ready**: Ownership can be transferred to a DAO smart contract
4. **One-Time Setup**: Critical access grants happen once at deployment and are locked
5. **Transparent Migration**: Clear path from centralized deployment → DAO governance → renounced ownership

## Contract Access Control

### 1. MarketFactory (Ownable2Step)

**Owner**: Deployer → Transferable to DAO

**Protected Functions:**
- `whitelistFeed(address feed, string description)` - Add Chainlink price feeds
- `delistFeed(address feed)` - Remove price feeds from whitelist
- `updateCreationFee(uint256 newFee)` - Change market creation fee
- `updateFeeTreasury(address newTreasury)` - Update fee recipient

**Immutable (No Access Control):**
- `createPriceAboveAtTime()` - Anyone can create markets (if they pay fee and use whitelisted feeds)

**Rationale:** 
- Feed whitelisting prevents malicious/manipulated price feeds
- Fee configuration allows protocol sustainability adjustments
- Market creation remains permissionless within whitelist bounds

---

### 2. Binary MarketCPMM

**Factory-Only Access:**
- `createMarket()` - Only MarketFactory can create markets
  - One-time setup via `setMarketFactory()` (callable once)

**Scheduler-Only Access:**
- `lockMarket()` - Only MarketScheduler can lock markets
- `resolveMarket()` - Only MarketScheduler can resolve outcomes

**Public Functions (No Access Control):**
- `buy()` - Anyone can trade
- `sell()` - Anyone can trade
- `redeem()` - Anyone can redeem winning shares

**Rationale:**
- Factory creates markets on behalf of users (handles USDC transfers)
- Scheduler automates resolution via Chainlink Automation
- Trading and redemption are fully permissionless

---

### 3. MarketScheduler

**Factory-Only Access:**
- `registerMarket()` - Only MarketFactory can register markets
  - One-time setup via `setMarketFactory()` (callable once)

**Automation-Only Access:**
- `performUpkeep()` - Only Chainlink Automation network can trigger resolution

**Public Functions:**
- `checkUpkeep()` - View function, callable by anyone

**Rationale:**
- Only factory can add markets to prevent spam/griefing
- Chainlink Automation is the trusted keeper for resolution
- No admin can manually interfere with settlement

---

### 4. OutcomeToken (ERC-1155)

**CPMM-Only Access:**
- `mint()` - Only BinaryMarketCPMM can mint tokens
- `burn()` - Only BinaryMarketCPMM can burn tokens

**Public Functions:**
- Standard ERC-1155 transfers (permissionless)

**Rationale:**
- Only CPMM should create/destroy outcome tokens to maintain market integrity
- Users can freely transfer their shares

---

### 5. OracleRouter

**No Access Control:**
- All functions are view/pure and publicly callable

**Rationale:**
- Pure oracle query logic requires no permissions

---

## Deployment Sequence

### Phase 1: Initial Deployment (Deployer = Owner)

```solidity
1. Deploy OutcomeToken (with predicted CPMM address)
2. Deploy BinaryMarketCPMM (with scheduler address)
3. Deploy MarketScheduler
4. Deploy MarketFactory (deployer as initial owner)
5. Call cpmm.setMarketFactory(factory) ✓ Locked forever
6. Call scheduler.setMarketFactory(factory) ✓ Locked forever
7. Whitelist initial price feeds (BTC/USD, ETH/USD, etc.)
```

**At this point:**
- Deployer can: whitelist feeds, adjust fees
- Deployer CANNOT: interfere with markets, trades, or resolution

### Phase 2: DAO Transfer (Optional)

```solidity
1. Deploy DAO/Governance contract (e.g., Governor + Timelock)
2. factory.transferOwnership(DAO_ADDRESS)
3. DAO accepts ownership via acceptOwnership()
```

**After transfer:**
- DAO can: whitelist feeds, adjust fees (via governance proposals)
- Deployer has zero control

### Phase 3: Renounced Ownership (Optional - "Immutable Mode")

```solidity
1. factory.renounceOwnership()
```

**After renouncement:**
- NO ONE can change feeds or fees
- Protocol is fully immutable (only existing whitelisted feeds work)
- New assets require deploying a new factory

---

## Security Considerations

### What Governance CAN Do

1. **Add new price feeds** - Expand to new assets (SOL, AVAX, etc.)
2. **Remove manipulated feeds** - Emergency response to oracle attacks
3. **Adjust creation fees** - Economic sustainability (0-100 USDC)
4. **Update fee treasury** - Change where protocol revenue goes

### What Governance CANNOT Do

1. ❌ Cancel or invalidate existing markets
2. ❌ Change market outcomes after resolution
3. ❌ Prevent users from trading or redeeming
4. ❌ Steal user funds or LP tokens
5. ❌ Pause the protocol
6. ❌ Upgrade contract logic (no proxies)

### Attack Vectors & Mitigation

**Risk: Malicious Feed Whitelisting**
- **Attack**: Owner whitelists a manipulated Chainlink feed
- **Mitigation**: 
  - Feed addresses are public and auditable
  - Only official Chainlink feeds should be whitelisted
  - DAO governance requires time-locked proposals (48hr+)
  - Community can verify feed legitimacy before proposal executes

**Risk: Excessive Creation Fees**
- **Attack**: Owner sets $1M creation fee to prevent market creation
- **Mitigation**:
  - Fee updates go through DAO governance (time-locked)
  - Community can fork the factory if governance acts maliciously
  - Users can deploy their own factory contract

**Risk: Factory/Scheduler Address Mistakes**
- **Attack**: Set wrong address during `setMarketFactory()`
- **Mitigation**:
  - One-time setup means careful verification is critical
  - Deployment script includes address verification
  - Test deployment on testnet first

---

## Governance Best Practices

### For Decentralized Launch

1. **Week 1-4**: Deployer retains ownership
   - Fast iteration on feed whitelisting
   - Monitor for oracle issues
   - Adjust fees based on gas costs

2. **Week 4-12**: Deploy DAO contracts
   - Governor (token voting or conviction voting)
   - Timelock (48-72 hour delay)
   - Emergency multisig (3/5 or 5/9)

3. **Week 12+**: Transfer to DAO
   - Test DAO proposals on testnet first
   - Execute ownership transfer
   - Verify DAO can execute feed whitelisting

4. **Year 1+**: Consider renouncing
   - Only if feed set is sufficient
   - Community votes on full immutability
   - No going back after renouncement

### For Anonymous Launch

1. **Deploy with anonymous wallet** (fresh address, no KYC)
2. **Whitelist 5-10 major feeds** (BTC, ETH, SOL, etc.)
3. **Renounce ownership immediately** or
4. **Transfer to DAO timelock** (if DAO ready)

---

## Emergency Response

### Scenario: Chainlink Feed Compromised

**Response:**
1. Governance calls `factory.delistFeed(maliciousAddress)`
2. Existing markets using that feed still resolve (cannot be stopped)
3. New markets cannot use delisted feed
4. Alternative feed can be whitelisted

### Scenario: USDC Depeg

**Response:**
- NO admin intervention possible
- Markets resolve based on Chainlink price feeds as designed
- Users decide whether to create new markets or not

### Scenario: Smart Contract Bug

**Response:**
- Contracts are immutable (no upgrades)
- Cannot pause or stop trading
- Must deploy new contracts if critical bug found
- Users decide whether to migrate to new version

---

## Audit Checklist

Before mainnet deployment:

- [ ] Verify `onlyFactory` modifier on `CPMM.createMarket()`
- [ ] Verify `onlyScheduler` modifier on `CPMM.lockMarket()` and `resolveMarket()`
- [ ] Verify `onlyCPMM` modifier on `OutcomeToken.mint()` and `burn()`
- [ ] Verify `onlyOwner` on all `MarketFactory` admin functions
- [ ] Verify `setMarketFactory()` can only be called once
- [ ] Test ownership transfer flow (deployer → DAO)
- [ ] Test ownership renouncement (if planned)
- [ ] Verify no hidden admin backdoors
- [ ] Verify no upgrade mechanisms (proxies, etc.)

---

## Code Examples

### Transferring Ownership to DAO

```solidity
// 1. Deploy Governor + Timelock
Governor gov = new Governor(...);
Timelock timelock = new Timelock(2 days, governors, executors);

// 2. Transfer ownership (deployer)
factory.transferOwnership(address(timelock));

// 3. Accept ownership (DAO executes)
timelock.execute(
    address(factory),
    0,
    abi.encodeWithSelector(factory.acceptOwnership.selector),
    bytes32(0),
    bytes32(0)
);
```

### Adding a Feed via DAO

```solidity
// 1. Create proposal
gov.propose(
    [address(factory)],
    [0],
    [abi.encodeWithSelector(
        factory.whitelistFeed.selector,
        0xSOL_USD_FEED_ADDRESS,
        "SOL/USD"
    )],
    "Whitelist Solana price feed"
);

// 2. Vote (quorum + majority)
// 3. Queue (timelock delay)
// 4. Execute after timelock
```

---

## References

- [OpenZeppelin Ownable2Step](https://docs.openzeppelin.com/contracts/4.x/api/access#Ownable2Step)
- [Chainlink Price Feeds](https://docs.chain.link/data-feeds)
- [Compound Governor](https://compound.finance/docs/governance)

---

**Last Updated**: October 25, 2025  
**Audit Status**: ⚠️ NOT AUDITED - Do not use in production without professional security review

