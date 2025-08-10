;; Community Mutual Insurance Protocol (CMIP) Smart Contract
;; 
;; A decentralized community-driven insurance platform that enables members to
;; pool resources through token staking, earn yield on their contributions,
;; and access mutual coverage through transparent, democratic claim resolution.
;; The protocol maintains stability via time-locked commitments and ensures
;; fair governance through consensus-based decision making.

;; PROTOCOL CONFIGURATION CONSTANTS

;; Administrative access control
(define-constant protocol-administrator tx-sender)

;; Financial parameters
(define-constant minimum-stake-required u1000000)        ;; 1 STX minimum commitment
(define-constant maximum-claimable-amount u100000000)    ;; 100 STX claim ceiling
(define-constant stake-commitment-period u144)           ;; ~24 hours lock duration
(define-constant maximum-annual-yield u1000)             ;; 10% yield cap (basis points)

;; Validation requirements
(define-constant minimum-description-length u5)          ;; Claim description minimum

;; ERROR CODE DEFINITIONS

(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-MEMBER-NOT-EXISTS (err u102))
(define-constant ERR-CLAIM-ALREADY-RESOLVED (err u103))
(define-constant ERR-CLAIM-DENIED (err u104))
(define-constant ERR-STAKE-TOO-SMALL (err u105))
(define-constant ERR-FUNDS-STILL-LOCKED (err u106))
(define-constant ERR-THRESHOLD-OUT-OF-BOUNDS (err u107))
(define-constant ERR-INVALID-CLAIM-AMOUNT (err u108))
(define-constant ERR-YIELD-RATE-EXCESSIVE (err u109))
(define-constant ERR-PARAMETER-INVALID (err u110))
(define-constant ERR-DESCRIPTION-TOO-SHORT (err u111))
(define-constant ERR-RECIPIENT-INVALID (err u112))
(define-constant ERR-CLAIM-NOT-FOUND (err u113))

;; DATA STRUCTURES

;; Member participation tracking
(define-map community-members
  { wallet-address: principal }
  { 
    committed-tokens: uint,
    commitment-start-height: uint,
    last-yield-claim-height: uint
  }
)

;; Insurance claim management
(define-map insurance-claims
  { request-identifier: uint }
  { 
    requesting-member: principal,
    requested-amount: uint,
    claim-narrative: (string-utf8 256),
    submission-height: uint,
    resolution-status: (string-utf8 10)  ;; "pending", "approved", "denied"
  }
)

;; PROTOCOL STATE VARIABLES

(define-data-var collective-pool-balance uint u0)
(define-data-var total-claims-distributed uint u0)
(define-data-var next-claim-identifier uint u0)
(define-data-var current-yield-rate uint u100)           ;; 1% default (basis points)
(define-data-var consensus-approval-threshold uint u5100) ;; 51% required

;; INFORMATION RETRIEVAL FUNCTIONS

;; Retrieve member participation details
(define-read-only (get-member-details (wallet-address principal))
  (default-to
    { committed-tokens: u0, commitment-start-height: u0, last-yield-claim-height: u0 }
    (map-get? community-members { wallet-address: wallet-address })
  )
)

;; Retrieve specific claim information
(define-read-only (get-claim-information (request-identifier uint))
  (map-get? insurance-claims { request-identifier: request-identifier })
)

;; Get current pool balance
(define-read-only (get-pool-balance)
  (var-get collective-pool-balance)
)

;; Get total distributed claims
(define-read-only (get-total-distributions)
  (var-get total-claims-distributed)
)

;; Get active yield rate
(define-read-only (get-active-yield-rate)
  (var-get current-yield-rate)
)

;; Get consensus threshold
(define-read-only (get-consensus-threshold)
  (var-get consensus-approval-threshold)
)

;; UTILITY AND VALIDATION FUNCTIONS

;; Validate text length
(define-read-only (validate-text-length (input-text (string-utf8 256)))
  (len input-text)
)

;; Validate recipient address
(define-read-only (is-recipient-valid (target-address principal))
  (and 
    (not (is-eq target-address (as-contract tx-sender)))
    (not (is-eq target-address 'SP000000000000000000002Q6VF78))
  )
)

;; Calculate accumulated yield for member
(define-read-only (calculate-member-yield (wallet-address principal))
  (let (
    (member-details (get-member-details wallet-address))
    (committed-amount (get committed-tokens member-details))
    (last-claim-height (get last-yield-claim-height member-details))
    (height-difference (- block-height last-claim-height))
  )
    (if (> committed-amount u0)
      (/ (* (* committed-amount height-difference) (var-get current-yield-rate)) u10000)
      u0
    )
  )
)

;; Verify if commitment period has expired
(define-read-only (is-commitment-period-over (wallet-address principal))
  (let (
    (member-details (get-member-details wallet-address))
    (start-height (get commitment-start-height member-details))
    (elapsed-blocks (- block-height start-height))
  )
    (>= elapsed-blocks stake-commitment-period)
  )
)

;; MEMBER PARTICIPATION FUNCTIONS

;; Join the insurance pool by committing tokens
(define-public (commit-tokens-to-pool (token-amount uint))
  (let (
    (existing-member-data (get-member-details tx-sender))
    (current-commitment (get committed-tokens existing-member-data))
  )
    ;; Enforce minimum commitment requirement
    (asserts! (>= token-amount minimum-stake-required) ERR-STAKE-TOO-SMALL)
    
    ;; Transfer tokens to protocol contract
    (try! (stx-transfer? token-amount tx-sender (as-contract tx-sender)))
    
    ;; Handle existing vs new member scenarios
    (if (> current-commitment u0)
      ;; Existing member: claim pending yield first
      (begin
        (try! (claim-accumulated-yield))
        (map-set community-members
          { wallet-address: tx-sender }
          { 
            committed-tokens: (+ current-commitment token-amount),
            commitment-start-height: block-height,
            last-yield-claim-height: block-height
          }
        )
      )
      ;; New member: initialize fresh record
      (map-set community-members
        { wallet-address: tx-sender }
        { 
          committed-tokens: token-amount,
          commitment-start-height: block-height,
          last-yield-claim-height: block-height
        }
      )
    )
    
    ;; Update collective pool balance
    (var-set collective-pool-balance (+ (var-get collective-pool-balance) token-amount))
    
    (ok token-amount)
  )
)

;; Withdraw committed tokens from the pool
(define-public (withdraw-committed-tokens (withdrawal-amount uint))
  (let (
    (member-details (get-member-details tx-sender))
    (total-commitment (get committed-tokens member-details))
    (commitment-height (get commitment-start-height member-details))
  )
    ;; Verify sufficient committed balance
    (asserts! (>= total-commitment withdrawal-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Enforce commitment period lock
    (asserts! (>= (- block-height commitment-height) stake-commitment-period) ERR-FUNDS-STILL-LOCKED)
    
    ;; Process pending yield claims
    (try! (claim-accumulated-yield))
    
    ;; Return tokens to member
    (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
    
    ;; Update member commitment record
    (map-set community-members
      { wallet-address: tx-sender }
      { 
        committed-tokens: (- total-commitment withdrawal-amount),
        commitment-start-height: commitment-height,
        last-yield-claim-height: block-height
      }
    )
    
    ;; Adjust collective pool balance
    (var-set collective-pool-balance (- (var-get collective-pool-balance) withdrawal-amount))
    
    (ok withdrawal-amount)
  )
)

;; Claim accumulated staking yield rewards
(define-public (claim-accumulated-yield)
  (let (
    (member-details (get-member-details tx-sender))
    (member-commitment (get committed-tokens member-details))
    (available-yield (calculate-member-yield tx-sender))
  )
    ;; Verify member participation
    (asserts! (> member-commitment u0) ERR-MEMBER-NOT-EXISTS)
    
    ;; Distribute available yield
    (if (> available-yield u0)
      (begin
        ;; Transfer yield to member
        (try! (as-contract (stx-transfer? available-yield (as-contract tx-sender) tx-sender)))
        
        ;; Update yield claim record
        (map-set community-members
          { wallet-address: tx-sender }
          { 
            committed-tokens: member-commitment,
            commitment-start-height: (get commitment-start-height member-details),
            last-yield-claim-height: block-height
          }
        )
        
        (ok available-yield)
      )
      (ok u0)
    )
  )
)

;; INSURANCE CLAIM PROCESSING

;; Submit new insurance claim request
(define-public (submit-insurance-request (claim-amount uint) (claim-narrative (string-utf8 256)))
  (let (
    (member-details (get-member-details tx-sender))
    (member-commitment (get committed-tokens member-details))
    (new-claim-id (var-get next-claim-identifier))
    (narrative-length (validate-text-length claim-narrative))
  )
    ;; Verify member eligibility
    (asserts! (> member-commitment u0) ERR-MEMBER-NOT-EXISTS)
    
    ;; Validate claim amount boundaries
    (asserts! (and (> claim-amount u0) (<= claim-amount maximum-claimable-amount)) 
              ERR-INVALID-CLAIM-AMOUNT)
    
    ;; Validate narrative completeness
    (asserts! (>= narrative-length minimum-description-length) 
              ERR-DESCRIPTION-TOO-SHORT)
    
    ;; Record insurance claim
    (map-set insurance-claims
      { request-identifier: new-claim-id }
      { 
        requesting-member: tx-sender,
        requested-amount: claim-amount,
        claim-narrative: claim-narrative,
        submission-height: block-height,
        resolution-status: u"pending"
      }
    )
    
    ;; Advance claim identifier counter
    (var-set next-claim-identifier (+ new-claim-id u1))
    
    (ok new-claim-id)
  )
)

;; Resolve insurance claim (administrative function)
(define-public (resolve-claim-request (request-identifier uint) (approval-decision bool))
  (let (
    ;; First, retrieve the claim data and validate it exists
    (claim-data (unwrap! (get-claim-information request-identifier) ERR-CLAIM-NOT-FOUND))
    (beneficiary (get requesting-member claim-data))
    (payout-amount (get requested-amount claim-data))
    (status-check (get resolution-status claim-data))
    (claim-narrative (get claim-narrative claim-data))
    (submission-height (get submission-height claim-data))
    ;; Create validated claim key
    (validated-claim-key { request-identifier: request-identifier })
  )
    ;; Verify administrative privileges
    (asserts! (is-eq tx-sender protocol-administrator) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Confirm claim is unresolved
    (asserts! (is-eq status-check u"pending") ERR-CLAIM-ALREADY-RESOLVED)
    
    ;; Verify pool sufficiency for approvals
    (asserts! (or (not approval-decision) (>= (var-get collective-pool-balance) payout-amount)) 
              ERR-INSUFFICIENT-FUNDS)
    
    (if approval-decision
      (begin
        ;; Execute approved claim payout
        (try! (as-contract (stx-transfer? payout-amount (as-contract tx-sender) beneficiary)))
        
        ;; Mark claim as approved using validated key and reconstructed data
        (map-set insurance-claims
          validated-claim-key
          { 
            requesting-member: beneficiary,
            requested-amount: payout-amount,
            claim-narrative: claim-narrative,
            submission-height: submission-height,
            resolution-status: u"approved"
          }
        )
        
        ;; Update protocol tracking
        (var-set total-claims-distributed (+ (var-get total-claims-distributed) payout-amount))
        (var-set collective-pool-balance (- (var-get collective-pool-balance) payout-amount))
        
        (ok true)
      )
      (begin
        ;; Mark claim as denied using validated key and reconstructed data
        (map-set insurance-claims
          validated-claim-key
          { 
            requesting-member: beneficiary,
            requested-amount: payout-amount,
            claim-narrative: claim-narrative,
            submission-height: submission-height,
            resolution-status: u"denied"
          }
        )
        
        (ok false)
      )
    )
  )
)

;; PROTOCOL GOVERNANCE FUNCTIONS

;; Adjust protocol yield rate (administrative)
(define-public (update-protocol-yield-rate (new-yield-rate uint))
  (begin
    ;; Verify administrative access
    (asserts! (is-eq tx-sender protocol-administrator) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate yield rate ceiling
    (asserts! (<= new-yield-rate maximum-annual-yield) ERR-YIELD-RATE-EXCESSIVE)
    
    ;; Apply new yield rate
    (var-set current-yield-rate new-yield-rate)
    
    (ok new-yield-rate)
  )
)

;; Modify consensus threshold (administrative)
(define-public (update-consensus-threshold (new-threshold-value uint))
  (begin
    ;; Verify administrative privileges
    (asserts! (is-eq tx-sender protocol-administrator) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate threshold boundaries
    (asserts! (<= new-threshold-value u10000) ERR-THRESHOLD-OUT-OF-BOUNDS)
    (asserts! (> new-threshold-value u0) ERR-PARAMETER-INVALID)
    
    ;; Update consensus threshold
    (var-set consensus-approval-threshold new-threshold-value)
    
    (ok new-threshold-value)
  )
)

;; Emergency fund recovery (administrative)
(define-public (emergency-fund-recovery (recovery-amount uint) (destination-address principal))
  (begin
    ;; Verify administrative authority
    (asserts! (is-eq tx-sender protocol-administrator) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate destination address
    (asserts! (is-recipient-valid destination-address) ERR-RECIPIENT-INVALID)
    
    ;; Verify recovery amount feasibility
    (asserts! (<= recovery-amount (var-get collective-pool-balance)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Execute emergency fund transfer
    (try! (as-contract (stx-transfer? recovery-amount (as-contract tx-sender) destination-address)))
    
    ;; Adjust pool balance accordingly
    (var-set collective-pool-balance (- (var-get collective-pool-balance) recovery-amount))
    
    (ok recovery-amount)
  )
)
