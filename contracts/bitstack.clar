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

