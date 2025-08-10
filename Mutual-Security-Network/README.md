# Community Mutual Insurance Protocol (CMIP)

A decentralized community-driven insurance platform built on the Stacks blockchain that enables members to pool resources through token staking, earn yield on their contributions, and access mutual coverage through transparent, democratic claim resolution.

## Overview

The Community Mutual Insurance Protocol creates a trustless insurance pool where community members can:
- Stake STX tokens to join the insurance pool
- Earn yield on their staked contributions
- Submit insurance claims for community review
- Participate in a mutual aid system with transparent governance

## Key Features

- **Community Pool**: Members contribute STX tokens to create a shared insurance fund
- **Yield Generation**: Earn returns on staked tokens based on configurable yield rates
- **Insurance Claims**: Submit and process insurance claims through the protocol
- **Time-locked Commitments**: Prevent gaming through mandatory lock periods
- **Administrative Controls**: Protocol governance through authorized administrators
- **Emergency Recovery**: Built-in mechanisms for fund recovery in extreme situations

## Protocol Parameters

### Financial Limits
- **Minimum Stake**: 1 STX (1,000,000 microSTX)
- **Maximum Claim**: 100 STX (100,000,000 microSTX)
- **Default Yield Rate**: 1% (100 basis points)
- **Maximum Yield Rate**: 10% (1,000 basis points)
- **Commitment Period**: 144 blocks (~24 hours)

### Governance
- **Consensus Threshold**: 51% (5,100 basis points)
- **Minimum Claim Description**: 5 characters

## Smart Contract Functions

### Member Participation

#### `commit-tokens-to-pool(token-amount: uint)`
Join the insurance pool by staking STX tokens.
- Requires minimum stake of 1 STX
- Creates or updates member record
- Automatically claims any pending yield for existing members

#### `withdraw-committed-tokens(withdrawal-amount: uint)`
Withdraw staked tokens from the pool.
- Requires commitment period to have passed
- Automatically claims pending yield before withdrawal
- Updates pool balance and member records

#### `claim-accumulated-yield()`
Claim earned yield on staked tokens.
- Calculates yield based on stake amount, time, and current yield rate
- Updates member's last claim height
- Transfers earned yield to member

### Insurance Claims

#### `submit-insurance-request(claim-amount: uint, claim-narrative: string)`
Submit a new insurance claim request.
- Requires active membership (staked tokens)
- Claim amount must be between 1 and 100 STX
- Requires descriptive narrative (minimum 5 characters)
- Returns unique claim identifier

#### `resolve-claim-request(request-identifier: uint, approval-decision: bool)`
**Administrative Function**: Approve or deny insurance claims.
- Only callable by protocol administrator
- Transfers funds to member if approved
- Updates claim status and protocol statistics

### Protocol Governance (Administrative Functions)

#### `update-protocol-yield-rate(new-yield-rate: uint)`
Adjust the yield rate for staked tokens.
- Maximum rate: 10% (1,000 basis points)

#### `update-consensus-threshold(new-threshold-value: uint)`
Modify the consensus threshold for governance decisions.
- Value must be between 1 and 10,000 basis points

#### `emergency-fund-recovery(recovery-amount: uint, destination-address: principal)`
Emergency function to recover funds from the protocol.
- Last resort for extreme situations
- Validates destination address
- Updates pool balance

### Read-Only Functions

#### Information Retrieval
- `get-member-details(wallet-address: principal)`: Get member participation data
- `get-claim-information(request-identifier: uint)`: Get specific claim details
- `get-pool-balance()`: Current total pool balance
- `get-total-distributions()`: Total claims paid out
- `get-active-yield-rate()`: Current yield rate
- `get-consensus-threshold()`: Current consensus threshold

#### Utility Functions
- `calculate-member-yield(wallet-address: principal)`: Calculate pending yield
- `is-commitment-period-over(wallet-address: principal)`: Check if tokens can be withdrawn
- `validate-text-length(input-text: string)`: Validate text input length
- `is-recipient-valid(target-address: principal)`: Validate recipient addresses

## Data Structures

### Member Records
```clarity
{
  committed-tokens: uint,
  commitment-start-height: uint,
  last-yield-claim-height: uint
}
```

### Insurance Claims
```clarity
{
  requesting-member: principal,
  requested-amount: uint,
  claim-narrative: string-utf8,
  submission-height: uint,
  resolution-status: string-utf8  // "pending", "approved", "denied"
}
```

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | ERR-UNAUTHORIZED-ACCESS | Caller lacks required permissions |
| 101 | ERR-INSUFFICIENT-FUNDS | Insufficient balance for operation |
| 102 | ERR-MEMBER-NOT-EXISTS | Member not found or not active |
| 103 | ERR-CLAIM-ALREADY-RESOLVED | Claim has already been processed |
| 104 | ERR-CLAIM-DENIED | Claim was rejected |
| 105 | ERR-STAKE-TOO-SMALL | Stake below minimum requirement |
| 106 | ERR-FUNDS-STILL-LOCKED | Commitment period not yet expired |
| 107 | ERR-THRESHOLD-OUT-OF-BOUNDS | Invalid consensus threshold value |
| 108 | ERR-INVALID-CLAIM-AMOUNT | Claim amount outside valid range |
| 109 | ERR-YIELD-RATE-EXCESSIVE | Yield rate exceeds maximum |
| 110 | ERR-PARAMETER-INVALID | Invalid parameter value |
| 111 | ERR-DESCRIPTION-TOO-SHORT | Claim description too brief |
| 112 | ERR-RECIPIENT-INVALID | Invalid recipient address |

## Usage Examples

### Joining the Pool
```clarity
;; Stake 5 STX to join the insurance pool
(contract-call? .cmip commit-tokens-to-pool u5000000)
```

### Submitting a Claim
```clarity
;; Submit claim for 2 STX with description
(contract-call? .cmip submit-insurance-request 
  u2000000 
  u"Medical emergency - hospital bills")
```

### Claiming Yield
```clarity
;; Claim any accumulated yield rewards
(contract-call? .cmip claim-accumulated-yield)
```

### Withdrawing Stake
```clarity
;; Withdraw 1 STX after commitment period
(contract-call? .cmip withdraw-committed-tokens u1000000)
```

## Security Considerations

1. **Time Locks**: All staked funds are locked for the commitment period to prevent gaming
2. **Administrative Controls**: Critical functions require administrator privileges
3. **Validation**: Extensive input validation and boundary checks
4. **Emergency Recovery**: Built-in mechanisms for extreme situations
5. **Yield Limits**: Maximum yield rates prevent excessive payouts

## Deployment Notes

- Set `protocol-administrator` to the appropriate administrative address
- Consider the economic implications of yield rates and pool dynamics
- Ensure adequate initial funding for yield payments
- Monitor pool balance relative to outstanding claims
- Regular governance review of parameters and thresholds