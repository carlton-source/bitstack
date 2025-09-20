;; Title: BitStack UBI - Decentralized Universal Basic Income Protocol
;; Summary: A Bitcoin-secured smart contract enabling sustainable UBI distribution 
;;          through community governance and transparent fund management
;; Description: BitStack UBI leverages Stacks' Bitcoin security to create a 
;;             decentralized universal basic income system. Participants register,
;;             undergo verification, and receive periodic STX distributions from
;;             a community-managed treasury. The protocol features democratic
;;             governance for parameter adjustments, emergency controls, and
;;             transparent tracking of all distributions and participant activity.
;;             Built for Bitcoin's Layer 2 ecosystem with enhanced security and
;;             economic sustainability at its core.

;; CONSTANTS & ERRORS

(define-constant CONTRACT-OWNER tx-sender)
(define-constant DISTRIBUTION-INTERVAL u144) ;; ~1 day in blocks
(define-constant MINIMUM-BALANCE u10000000) ;; Minimum treasury balance (10 STX)
(define-constant MAX-PROPOSED-VALUE u1000000000000) ;; Maximum governance proposal value
(define-constant PROPOSAL-VOTING-PERIOD u1440) ;; ~10 days in blocks

;; Error codes with descriptive naming
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INELIGIBLE (err u103))
(define-constant ERR-COOLDOWN-ACTIVE (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-UNAUTHORIZED (err u107))
(define-constant ERR-INVALID-PROPOSAL (err u108))
(define-constant ERR-EXPIRED-PROPOSAL (err u109))
(define-constant ERR-INVALID-VALUE (err u110))
(define-constant ERR-ALREADY-VOTED (err u111))
(define-constant ERR-CONTRACT-PAUSED (err u112))

;; DATA VARIABLES

(define-data-var treasury-balance uint u0)
(define-data-var total-participants uint u0)
(define-data-var distribution-amount uint u1000000) ;; 1 STX = 1,000,000 microSTX
(define-data-var last-distribution-height uint u0)
(define-data-var paused bool false)
(define-data-var proposal-counter uint u0)

;; DATA MAPS

;; Participant registry with comprehensive tracking
(define-map participants
  principal
  {
    registered: bool,
    last-claim-height: uint,
    total-claimed: uint,
    verification-status: bool,
    join-height: uint,
    claims-count: uint,
  }
)

;; Governance proposal system
(define-map governance-proposals
  uint
  {
    proposer: principal,
    proposal-type: (string-ascii 32),
    proposed-value: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 10),
    expiry-height: uint,
  }
)

;; Voting records to prevent double voting
(define-map voter-records
  {
    proposal-id: uint,
    voter: principal,
  }
  bool
)

;; PRIVATE FUNCTIONS

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Validate participant eligibility for UBI claim
(define-private (is-eligible (user principal))
  (match (map-get? participants user)
    participant-info (and
      (get verification-status participant-info)
      (>= (- stacks-block-height (get last-claim-height participant-info))
        DISTRIBUTION-INTERVAL
      )
      (>= (var-get treasury-balance) (var-get distribution-amount))
      (not (var-get paused))
    )
    false
  )
)

;; Update participant record after successful claim
(define-private (update-participant-record
    (user principal)
    (claimed-amount uint)
  )
  (match (map-get? participants user)
    current-info (ok (map-set participants user
      (merge current-info {
        last-claim-height: stacks-block-height,
        total-claimed: (+ (get total-claimed current-info) claimed-amount),
        claims-count: (+ (get claims-count current-info) u1),
      })
    ))
    ERR-NOT-REGISTERED
  )
)

;; Validate governance proposal types
(define-private (is-valid-proposal-type (proposal-type (string-ascii 32)))
  (or
    (is-eq proposal-type "distribution-amount")
    (is-eq proposal-type "distribution-interval")
    (is-eq proposal-type "minimum-balance")
  )
)

;; Validate proposed values for governance
(define-private (is-valid-proposed-value (value uint))
  (and
    (> value u0)
    (<= value MAX-PROPOSED-VALUE)
  )
)

;; PUBLIC FUNCTIONS

;; Register new participant in BitStack UBI
(define-public (register)
  (let ((existing-record (map-get? participants tx-sender)))
    (asserts! (is-none existing-record) ERR-ALREADY-REGISTERED)
    (asserts! (not (var-get paused)) ERR-CONTRACT-PAUSED)
    (map-set participants tx-sender {
      registered: true,
      last-claim-height: u0,
      total-claimed: u0,
      verification-status: false,
      join-height: stacks-block-height,
      claims-count: u0,
    })
    (var-set total-participants (+ (var-get total-participants) u1))
    (ok true)
  )
)

;; Verify participant (admin only)
(define-public (verify-participant (user principal))
  (begin
    (asserts! (is-contract-owner) ERR-OWNER-ONLY)
    (asserts! (is-some (map-get? participants user)) ERR-NOT-REGISTERED)
    (map-set participants user
      (merge (unwrap! (map-get? participants user) ERR-NOT-REGISTERED) { verification-status: true })
    )
    (ok true)
  )
)

;; Claim UBI distribution
(define-public (claim-ubi)
  (let (
      (user tx-sender)
      (distribution-amt (var-get distribution-amount))
    )
    (asserts! (not (var-get paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eligible user) ERR-INELIGIBLE)
    (asserts! (>= (var-get treasury-balance) distribution-amt)
      ERR-INSUFFICIENT-FUNDS
    )
    ;; Transfer STX to participant
    (try! (as-contract (stx-transfer? distribution-amt tx-sender user)))
    ;; Update treasury and participant records
    (var-set treasury-balance (- (var-get treasury-balance) distribution-amt))
    (try! (update-participant-record user distribution-amt))
    (ok distribution-amt)
  )
)

;; Contribute funds to treasury
(define-public (contribute (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (var-get paused)) ERR-CONTRACT-PAUSED)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok amount)
  )
)

;; GOVERNANCE SYSTEM

;; Submit governance proposal
(define-public (submit-proposal
    (proposal-type (string-ascii 32))
    (proposed-value uint)
  )
  (let ((new-proposal-id (+ (var-get proposal-counter) u1)))
    (asserts! (is-some (map-get? participants tx-sender)) ERR-NOT-REGISTERED)
    (asserts! (is-valid-proposal-type proposal-type) ERR-INVALID-PROPOSAL)
    (asserts! (is-valid-proposed-value proposed-value) ERR-INVALID-VALUE)
    (asserts! (not (var-get paused)) ERR-CONTRACT-PAUSED)
    (map-set governance-proposals new-proposal-id {
      proposer: tx-sender,
      proposal-type: proposal-type,
      proposed-value: proposed-value,
      votes-for: u0,
      votes-against: u0,
      status: "active",
      expiry-height: (+ stacks-block-height PROPOSAL-VOTING-PERIOD),
    })
    (var-set proposal-counter new-proposal-id)
    (ok new-proposal-id)
  )
)

;; Vote on governance proposal
(define-public (vote
    (proposal-id uint)
    (vote-for bool)
  )
  (let (
      (proposal (unwrap! (map-get? governance-proposals proposal-id) ERR-INVALID-PROPOSAL))
      (voter-key {
        proposal-id: proposal-id,
        voter: tx-sender,
      })
    )
    (asserts! (is-some (map-get? participants tx-sender)) ERR-NOT-REGISTERED)
    (asserts! (is-none (map-get? voter-records voter-key)) ERR-ALREADY-VOTED)
    (asserts! (<= proposal-id (var-get proposal-counter)) ERR-INVALID-PROPOSAL)
    (asserts! (< stacks-block-height (get expiry-height proposal))
      ERR-EXPIRED-PROPOSAL
    )
    (asserts! (is-eq (get status proposal) "active") ERR-INVALID-PROPOSAL)
    ;; Record vote
    (map-set voter-records voter-key true)
    (map-set governance-proposals proposal-id
      (merge proposal {
        votes-for: (if vote-for
          (+ (get votes-for proposal) u1)
          (get votes-for proposal)
        ),
        votes-against: (if vote-for
          (get votes-against proposal)
          (+ (get votes-against proposal) u1)
        ),
      })
    )
    (ok true)
  )
)

;; EMERGENCY FUNCTIONS

;; Pause contract operations
(define-public (pause)
  (begin
    (asserts! (is-contract-owner) ERR-OWNER-ONLY)
    (var-set paused true)
    (ok true)
  )
)

;; Resume contract operations
(define-public (unpause)
  (begin
    (asserts! (is-contract-owner) ERR-OWNER-ONLY)
    (var-set paused false)
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS

;; Get participant information
(define-read-only (get-participant-info (user principal))
  (map-get? participants user)
)

;; Get current treasury balance
(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

;; Get governance proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals proposal-id)
)

;; Get distribution configuration
(define-read-only (get-distribution-info)
  {
    amount: (var-get distribution-amount),
    interval: DISTRIBUTION-INTERVAL,
    last-height: (var-get last-distribution-height),
    minimum-balance: MINIMUM-BALANCE,
    total-participants: (var-get total-participants),
  }
)

;; Check if user can claim UBI
(define-read-only (can-claim-ubi (user principal))
  (is-eligible user)
)

;; Get contract status
(define-read-only (get-contract-status)
  {
    paused: (var-get paused),
    owner: CONTRACT-OWNER,
    total-proposals: (var-get proposal-counter),
  }
)
