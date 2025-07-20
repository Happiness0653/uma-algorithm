;; Uma Rental Algorithm
;; A decentralized rental protocol that enables secure, transparent property leasing on the Stacks blockchain

;; Error constants for precise state management
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-PARAMETERS (err u101))
(define-constant ERR-RESOURCE-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-ALREADY-EXISTS (err u105))
(define-constant ERR-DISPUTE-CONSTRAINT (err u106))

;; Lease lifecycle status constants
(define-constant STATUS-DRAFT u1)
(define-constant STATUS-ACTIVE u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-TERMINATED u4)
(define-constant STATUS-DISPUTED u5)

;; Platform configuration variables
(define-data-var protocol-fee-bps uint u250) ;; Default 2.5% fee
(define-data-var protocol-owner principal tx-sender)

;; Main data structures
(define-map rental-properties
  { property-id: uint }
  {
    owner: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    monthly-rate: uint,
    security-deposit: uint,
    status: uint,
    created-at: uint
  }
)

(define-map rental-agreements
  { agreement-id: uint }
  {
    property-id: uint,
    tenant: principal,
    landlord: principal,
    start-block: uint,
    end-block: uint,
    monthly-payment: uint,
    status: uint,
    last-payment-block: uint
  }
)

;; Counters for unique identifiers
(define-data-var next-property-id uint u1)
(define-data-var next-agreement-id uint u1)

;; Private utility functions
(define-private (generate-property-id)
  (let ((current-id (var-get next-property-id)))
    (var-set next-property-id (+ current-id u1))
    current-id
  )
)

(define-private (generate-agreement-id)
  (let ((current-id (var-get next-agreement-id)))
    (var-set next-agreement-id (+ current-id u1))
    current-id
  )
)

;; Read-only functions for retrieving state
(define-read-only (get-property (property-id uint))
  (map-get? rental-properties { property-id: property-id })
)

(define-read-only (get-agreement (agreement-id uint))
  (map-get? rental-agreements { agreement-id: agreement-id })
)

;; Property registration function
(define-public (register-property
  (title (string-utf8 100))
  (description (string-utf8 500))
  (monthly-rate uint)
  (security-deposit uint)
)
  (let ((property-id (generate-property-id)))
    (asserts! (> monthly-rate u0) ERR-INVALID-PARAMETERS)
    (asserts! (> security-deposit u0) ERR-INVALID-PARAMETERS)
    
    (map-set rental-properties
      { property-id: property-id }
      {
        owner: tx-sender,
        title: title,
        description: description,
        monthly-rate: monthly-rate,
        security-deposit: security-deposit,
        status: STATUS-DRAFT,
        created-at: block-height
      }
    )
    
    (ok property-id)
  )
)

;; Agreement creation function
(define-public (create-agreement
  (property-id uint)
  (start-block uint)
  (end-block uint)
)
  (let (
    (property (unwrap! (map-get? rental-properties { property-id: property-id }) ERR-RESOURCE-NOT-FOUND))
    (agreement-id (generate-agreement-id))
  )
    (asserts! (is-eq (get status property) STATUS-DRAFT) ERR-INVALID-STATE)
    (asserts! (> end-block start-block) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq tx-sender (get owner property))) ERR-UNAUTHORIZED)
    
    ;; Security deposit transfer
    (unwrap! (stx-transfer? (get security-deposit property) tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-BALANCE)
    
    (map-set rental-agreements
      { agreement-id: agreement-id }
      {
        property-id: property-id,
        tenant: tx-sender,
        landlord: (get owner property),
        start-block: start-block,
        end-block: end-block,
        monthly-payment: (get monthly-rate property),
        status: STATUS-ACTIVE,
        last-payment-block: start-block
      }
    )
    
    ;; Update property status
    (map-set rental-properties
      { property-id: property-id }
      (merge property { status: STATUS-ACTIVE })
    )
    
    (ok agreement-id)
  )
)

;; Monthly rent payment function
(define-public (pay-monthly-rent (agreement-id uint))
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-RESOURCE-NOT-FOUND))
    (rent-amount (get monthly-payment agreement))
    (protocol-fee (/ (* rent-amount (var-get protocol-fee-bps)) u10000))
    (landlord-amount (- rent-amount protocol-fee))
  )
    (asserts! (is-eq tx-sender (get tenant agreement)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status agreement) STATUS-ACTIVE) ERR-INVALID-STATE)
    
    ;; Transfer rent: to landlord and protocol
    (unwrap! (stx-transfer? landlord-amount tx-sender (get landlord agreement)) ERR-INSUFFICIENT-BALANCE)
    (unwrap! (stx-transfer? protocol-fee tx-sender (var-get protocol-owner)) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update agreement last payment block
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { last-payment-block: block-height })
    )
    
    (ok true)
  )
)

;; Agreement termination function
(define-public (terminate-agreement (agreement-id uint))
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-RESOURCE-NOT-FOUND))
    (property (unwrap! (map-get? rental-properties { property-id: (get property-id agreement) }) ERR-RESOURCE-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender (get tenant agreement)) (is-eq tx-sender (get landlord agreement))) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status agreement) STATUS-ACTIVE) ERR-INVALID-STATE)
    
    ;; Refund security deposit
    (as-contract
      (unwrap! (stx-transfer? (get security-deposit property) tx-sender (get tenant agreement)) ERR-INSUFFICIENT-BALANCE)
    )
    
    ;; Update agreement and property status
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { status: STATUS-TERMINATED })
    )
    
    (map-set rental-properties
      { property-id: (get property-id agreement) }
      (merge property { status: STATUS-DRAFT })
    )
    
    (ok true)
  )
)

;; Administrative functions
(define-public (update-protocol-fee (new-fee-bps uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee-bps u1000) ERR-INVALID-PARAMETERS) ;; Max 10%
    (var-set protocol-fee-bps new-fee-bps)
    (ok true)
  )
)

(define-public (transfer-protocol-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-UNAUTHORIZED)
    (var-set protocol-owner new-owner)
    (ok true)
  )
)