;; Beneficiary Coordination Contract
;; Ensures proper inheritance distribution and documentation

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-BENEFICIARY-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-CLAIM-ALREADY-EXISTS (err u303))
(define-constant ERR-CLAIM-NOT-FOUND (err u304))
(define-constant ERR-DISPUTE-ACTIVE (err u305))

;; Data Variables
(define-data-var beneficiary-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var dispute-counter uint u0)

;; Data Maps
(define-map beneficiaries
  { beneficiary-id: uint }
  {
    principal-address: principal,
    full-name: (string-ascii 100),
    relationship: (string-ascii 50),
    contact-info: (string-ascii 200),
    is-verified: bool,
    created-at: uint
  }
)

(define-map inheritance-claims
  { claim-id: uint }
  {
    beneficiary-id: uint,
    estate-id: uint,
    claimed-amount: uint,
    claim-type: (string-ascii 50),
    documentation-hash: (buff 32),
    status: (string-ascii 20),
    filed-at: uint,
    processed-at: (optional uint)
  }
)

(define-map beneficiary-disputes
  { dispute-id: uint }
  {
    claim-id: uint,
    disputing-party: principal,
    dispute-reason: (string-ascii 200),
    evidence-hash: (buff 32),
    status: (string-ascii 20),
    filed-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map estate-beneficiaries
  { estate-id: uint }
  { beneficiary-ids: (list 20 uint) }
)

(define-map beneficiary-allocations
  { estate-id: uint, beneficiary-id: uint }
  {
    allocated-amount: uint,
    allocation-percentage: uint,
    conditions: (string-ascii 200),
    is-conditional: bool
  }
)

;; Read-only functions
(define-read-only (get-beneficiary (beneficiary-id uint))
  (map-get? beneficiaries { beneficiary-id: beneficiary-id })
)

(define-read-only (get-inheritance-claim (claim-id uint))
  (map-get? inheritance-claims { claim-id: claim-id })
)

(define-read-only (get-beneficiary-dispute (dispute-id uint))
  (map-get? beneficiary-disputes { dispute-id: dispute-id })
)

(define-read-only (get-estate-beneficiaries (estate-id uint))
  (default-to { beneficiary-ids: (list) } (map-get? estate-beneficiaries { estate-id: estate-id }))
)

(define-read-only (get-beneficiary-allocation (estate-id uint) (beneficiary-id uint))
  (map-get? beneficiary-allocations { estate-id: estate-id, beneficiary-id: beneficiary-id })
)

(define-read-only (get-counters)
  {
    beneficiary-counter: (var-get beneficiary-counter),
    claim-counter: (var-get claim-counter),
    dispute-counter: (var-get dispute-counter)
  }
)

;; Private functions
(define-private (add-beneficiary-to-estate (estate-id uint) (beneficiary-id uint))
  (let ((current-beneficiaries (get beneficiary-ids (get-estate-beneficiaries estate-id))))
    (ok (map-set estate-beneficiaries
      { estate-id: estate-id }
      { beneficiary-ids: (unwrap! (as-max-len? (append current-beneficiaries beneficiary-id) u20) ERR-INVALID-INPUT) }
    ))
  )
)

;; Public functions
(define-public (register-beneficiary (full-name (string-ascii 100)) (relationship (string-ascii 50)) (contact-info (string-ascii 200)))
  (let ((beneficiary-id (+ (var-get beneficiary-counter) u1)))
    (asserts! (> (len full-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len relationship) u0) ERR-INVALID-INPUT)

    (map-set beneficiaries
      { beneficiary-id: beneficiary-id }
      {
        principal-address: tx-sender,
        full-name: full-name,
        relationship: relationship,
        contact-info: contact-info,
        is-verified: false,
        created-at: block-height
      }
    )

    (var-set beneficiary-counter beneficiary-id)
    (ok beneficiary-id)
  )
)

(define-public (verify-beneficiary (beneficiary-id uint))
  (let ((beneficiary-data (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set beneficiaries
      { beneficiary-id: beneficiary-id }
      (merge beneficiary-data { is-verified: true })
    )

    (ok true)
  )
)

(define-public (add-beneficiary-to-estate-plan (estate-id uint) (beneficiary-id uint) (allocated-amount uint) (allocation-percentage uint) (conditions (string-ascii 200)))
  (let ((beneficiary-data (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND)))
    (asserts! (get is-verified beneficiary-data) ERR-NOT-AUTHORIZED)
    (asserts! (<= allocation-percentage u100) ERR-INVALID-INPUT)

    (map-set beneficiary-allocations
      { estate-id: estate-id, beneficiary-id: beneficiary-id }
      {
        allocated-amount: allocated-amount,
        allocation-percentage: allocation-percentage,
        conditions: conditions,
        is-conditional: (> (len conditions) u0)
      }
    )

    (try! (add-beneficiary-to-estate estate-id beneficiary-id))
    (ok true)
  )
)

(define-public (file-inheritance-claim (beneficiary-id uint) (estate-id uint) (claimed-amount uint) (claim-type (string-ascii 50)) (documentation-hash (buff 32)))
  (let (
    (claim-id (+ (var-get claim-counter) u1))
    (beneficiary-data (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get principal-address beneficiary-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-verified beneficiary-data) ERR-NOT-AUTHORIZED)
    (asserts! (> claimed-amount u0) ERR-INVALID-INPUT)

    (map-set inheritance-claims
      { claim-id: claim-id }
      {
        beneficiary-id: beneficiary-id,
        estate-id: estate-id,
        claimed-amount: claimed-amount,
        claim-type: claim-type,
        documentation-hash: documentation-hash,
        status: "pending",
        filed-at: block-height,
        processed-at: none
      }
    )

    (var-set claim-counter claim-id)
    (ok claim-id)
  )
)

(define-public (process-inheritance-claim (claim-id uint) (approved bool))
  (let ((claim-data (unwrap! (get-inheritance-claim claim-id) ERR-CLAIM-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status claim-data) "pending") ERR-NOT-AUTHORIZED)

    (map-set inheritance-claims
      { claim-id: claim-id }
      (merge claim-data {
        status: (if approved "approved" "rejected"),
        processed-at: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (file-beneficiary-dispute (claim-id uint) (dispute-reason (string-ascii 200)) (evidence-hash (buff 32)))
  (let (
    (dispute-id (+ (var-get dispute-counter) u1))
    (claim-data (unwrap! (get-inheritance-claim claim-id) ERR-CLAIM-NOT-FOUND))
  )
    (asserts! (> (len dispute-reason) u0) ERR-INVALID-INPUT)

    (map-set beneficiary-disputes
      { dispute-id: dispute-id }
      {
        claim-id: claim-id,
        disputing-party: tx-sender,
        dispute-reason: dispute-reason,
        evidence-hash: evidence-hash,
        status: "open",
        filed-at: block-height,
        resolved-at: none
      }
    )

    (var-set dispute-counter dispute-id)
    (ok dispute-id)
  )
)

(define-public (resolve-beneficiary-dispute (dispute-id uint) (resolution (string-ascii 20)))
  (let ((dispute-data (unwrap! (get-beneficiary-dispute dispute-id) ERR-CLAIM-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status dispute-data) "open") ERR-NOT-AUTHORIZED)

    (map-set beneficiary-disputes
      { dispute-id: dispute-id }
      (merge dispute-data {
        status: resolution,
        resolved-at: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (update-beneficiary-info (beneficiary-id uint) (contact-info (string-ascii 200)))
  (let ((beneficiary-data (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get principal-address beneficiary-data)) ERR-NOT-AUTHORIZED)

    (map-set beneficiaries
      { beneficiary-id: beneficiary-id }
      (merge beneficiary-data { contact-info: contact-info })
    )

    (ok true)
  )
)
