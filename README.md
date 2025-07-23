# Time Lock - STX Smart Contract

An advanced time-locked asset management system for Stacks blockchain that enables secure, conditional, and scheduled STX distributions with support for multiple beneficiaries, vesting schedules, and customizable release conditions.

## Overview

Time Lock is a production-ready smart contract that revolutionizes how STX assets are managed over time. It enables:

- **Time-locked Vaults**: Secure STX until specific block heights
- **Multi-beneficiary Support**: Distribute to up to 10 beneficiaries with custom percentages
- **Vesting Schedules**: Create gradual release schedules for employee compensation or investments
- **Conditional Releases**: Set custom conditions for fund release (price targets, block milestones)
- **Cancellation Rights**: Flexible cancellation permissions for creators and beneficiaries

## Use Cases

### 1. **Inheritance Planning**
Create time-locked vaults that distribute assets to beneficiaries after a specific time or condition.

### 2. **Employee Vesting**
Set up vesting schedules for employee STX compensation with cliff periods and gradual releases.

### 3. **Escrow Services**
Lock funds until specific conditions are met, with multi-party release approval.

### 4. **Scheduled Payments**
Automate future payments for subscriptions, salaries, or installments.

### 5. **Trust Funds**
Create trust-like structures with controlled distribution schedules.

## Features

### Core Functionality
- **Create Lock**: Lock STX with custom unlock conditions and beneficiaries
- **Vesting Locks**: Create locks with gradual release schedules
- **Claim Funds**: Beneficiaries claim their share when conditions are met
- **Cancel Lock**: Authorized parties can cancel and refund remaining funds

### Security Features
- **Multi-beneficiary Validation**: Ensures percentages always total 100%
- **Claimed Tracking**: Prevents double-claiming with precise accounting
- **Emergency Pause**: Admin can pause new lock creation in emergencies
- **Cancellation Permissions**: Granular control over who can cancel locks
- **Fee Protection**: Protocol fees ensure sustainable operation

### Advanced Features
- **Conditional Logic**: Support for price-based and block-based conditions
- **Vesting Calculations**: Automatic calculation of available vesting amounts
- **Beneficiary Management**: Track locks per beneficiary for easy portfolio view
- **Creator Dashboard**: Track all created locks in one place

## Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd TimeLock

# Install Clarinet
# Visit: https://github.com/hirosystems/clarinet

# Check contract validity
clarinet check

# Run tests
clarinet test
```

## Contract Functions

### Core Functions

#### `create-lock(amount, unlock-height, beneficiaries)`
Create a standard time-locked vault.

```clarity
;; Lock 100 STX until block 100000 for two beneficiaries
(contract-call? .timelock create-lock 
  u100000000 
  u100000
  (list 
    {beneficiary: 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7, percentage: u5000, can-cancel: false}
    {beneficiary: 'SP3J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ8, percentage: u5000, can-cancel: true}
  )
)
```

#### `create-vesting-lock(amount, unlock-height, vesting-period, releases, beneficiaries)`
Create a vesting schedule with gradual releases.

```clarity
;; Create 4-year vesting with monthly releases
(contract-call? .timelock create-vesting-lock 
  u1000000000  ;; 1000 STX
  u100000      ;; Cliff at block 100000
  u4320        ;; Monthly (30 days in blocks)
  u48          ;; 48 releases (4 years)
  (list {beneficiary: 'SP2...', percentage: u10000, can-cancel: false})
)
```

#### `claim(lock-id)`
Claim available funds from a lock.

```clarity
;; Claim from lock ID 1
(contract-call? .timelock claim u1)
```

#### `cancel-lock(lock-id)`
Cancel a lock if authorized.

```clarity
;; Cancel lock ID 1
(contract-call? .timelock cancel-lock u1)
```

### Read-Only Functions

#### `get-lock(lock-id)`
Get complete lock information.

#### `get-lock-beneficiaries(lock-id)`
Get list of beneficiaries for a lock.

#### `calculate-vesting-amount(lock-id, beneficiary)`
Calculate available vesting amount for a beneficiary.

#### `is-unlocked(lock-id)`
Check if a lock's conditions are met.

## Usage Examples

### Example 1: Simple Time Lock
```clarity
;; Parent locks 50 STX for child until they turn 18
(contract-call? .timelock create-lock 
  u50000000   ;; 50 STX
  u126144000  ;; ~2 years in blocks
  (list {
    beneficiary: 'SP_CHILD_ADDRESS', 
    percentage: u10000,  ;; 100%
    can-cancel: false
  })
)
```

### Example 2: Multi-Beneficiary Inheritance
```clarity
;; Estate planning with multiple beneficiaries
(contract-call? .timelock create-lock 
  u1000000000  ;; 1000 STX
  u252288000   ;; ~4 years
  (list 
    {beneficiary: 'SP_SPOUSE', percentage: u5000, can-cancel: false}      ;; 50%
    {beneficiary: 'SP_CHILD1', percentage: u2500, can-cancel: false}      ;; 25%
    {beneficiary: 'SP_CHILD2', percentage: u2500, can-cancel: false}      ;; 25%
  )
)
```

### Example 3: Employee Vesting
```clarity
;; 4-year vesting with 1-year cliff
(contract-call? .timelock create-vesting-lock 
  u400000000   ;; 400 STX total
  u63072000    ;; 1-year cliff (~365 days)
  u4320        ;; Monthly releases
  u36          ;; 36 months after cliff
  (list {
    beneficiary: 'SP_EMPLOYEE', 
    percentage: u10000,
    can-cancel: true  ;; Company can cancel if employee leaves
  })
)
```

## Contract Architecture

### Data Structures

#### Lock Structure
```clarity
{
  creator: principal,
  amount: uint,
  unlock-height: uint,
  created-height: uint,
  is-cancelled: bool,
  is-vesting: bool,
  vesting-period: uint,
  vesting-releases: uint,
  condition-type: (string-ascii 20),
  condition-value: uint
}
```

#### Beneficiary Structure
```clarity
{
  beneficiary: principal,
  percentage: uint,      ;; In basis points (10000 = 100%)
  claimed: uint,         ;; Amount already claimed
  can-cancel: bool       ;; Can this beneficiary cancel the lock
}
```

## Fee Structure

| Fee Type | Default | Maximum | Description |
|----------|---------|---------|-------------|
| Protocol Fee | 0.25% | 10% | Charged on all claims |

## Security Considerations

1. **Percentage Validation**: All beneficiary percentages must sum to exactly 10000 (100%)
2. **Double-Claim Prevention**: Contract tracks claimed amounts per beneficiary
3. **Time Validation**: Unlock heights must be in the future
4. **Cancellation Rights**: Only authorized parties can cancel locks
5. **Emergency Controls**: Owner can pause new lock creation

## Testing

```typescript
// tests/timelock_test.ts
import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';

Clarinet.test({
    name: "Create and claim time lock",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        let wallet_1 = accounts.get('wallet_1')!;
        let wallet_2 = accounts.get('wallet_2')!;
        
        // Create lock
        let block = chain.mineBlock([
            Tx.contractCall('timelock', 'create-lock', [
                types.uint(1000000),  // 1 STX
                types.uint(chain.blockHeight + 10),
                types.list([{
                    beneficiary: types.principal(wallet_2.address),
                    percentage: types.uint(10000),
                    'can-cancel': types.bool(false)
                }])
            ], wallet_1.address)
        ]);
        
        block.receipts[0].result.expectOk();
        
        // Mine blocks to unlock
        chain.mineEmptyBlockUntil(chain.blockHeight + 11);
        
        // Claim
        let claimBlock = chain.mineBlock([
            Tx.contractCall('timelock', 'claim', [
                types.uint(0)  // lock-id
            ], wallet_2.address)
        ]);
        
        claimBlock.receipts[0].result.expectOk();
    }
});
```

## Deployment

1. **Configure Parameters**
```clarity
;; Update constants before deployment
(define-constant max-beneficiaries u10)    ;; Maximum beneficiaries per lock
(define-data-var protocol-fee u25)        ;; 0.25% fee
```

2. **Deploy Contract**
```bash
# Deploy to testnet
clarinet deploy --testnet

# Or using Stacks CLI
stacks deploy timelock.clar --testnet
```

3. **Set Treasury**
```clarity
;; Set treasury address for fee collection
(contract-call? .timelock set-treasury 'SP_TREASURY_ADDRESS)
```

## Advanced Usage

### Conditional Releases
Future versions will support:
- **Price Conditions**: Release when STX price reaches target
- **Oracle Integration**: External data for release conditions
- **Multi-sig Approvals**: Require multiple signatures for release

### Integration Ideas
- **DeFi Protocols**: Lock liquidity provider rewards
- **DAOs**: Lock governance tokens with vesting
- **NFT Projects**: Time-locked NFT sale proceeds

## Roadmap

- [ ] Price oracle integration
- [ ] Multi-signature release conditions
- [ ] Partial cancellation support
- [ ] Lock transfer functionality
- [ ] Notification system for beneficiaries
- [ ] Web interface for lock management

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

MIT License - see LICENSE file for details

## Disclaimer

This smart contract handles valuable assets. Always:
- Audit the code before mainnet deployment
- Test thoroughly with small amounts first
- Verify all beneficiary addresses
- Understand the cancellation policies

## Support

- GitHub Issues: [Report bugs or request features]
- Discord: [Join our community]
- Documentation: [Full API reference]
