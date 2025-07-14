;; Executor Support Contract
;; Assists designated individuals with estate administration duties

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-ESTATE-NOT-FOUND (err u501))
(define-constant ERR-TASK-NOT-FOUND (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-EXECUTOR-NOT-FOUND (err u504))
(define-constant ERR-TASK-ALREADY-COMPLETED (err u505))

;; Data Variables
(define-data-var estate-counter uint u0)
(define-data-var task-counter uint u0)
(define-data-var executor-counter uint u0)

;; Data Maps
(define-map executor-estates
  { estate-id: uint }
  {
    deceased-owner: principal,
    primary-executor: principal,
    backup-executor: (optional principal),
    estate-value: uint,
    probate-status: (string-ascii 30),
    created-at: uint,
    probate-started: (optional uint),
    probate-completed: (optional uint)
  }
)

(define-map executor-tasks
  { task-id: uint }
  {
    estate-id: uint,
    task-name: (string-ascii 100),
    task-category: (string-ascii 50),
    description: (string-ascii 300),
    priority-level: uint,
    due-date: (optional uint),
    assigned-to: principal,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map executor-compensation
  { estate-id: uint, executor: principal }
  {
    base-fee: uint,
    hourly-rate: uint,
    hours-worked: uint,
    expenses-incurred: uint,
    total-compensation: uint,
    payment-status: (string-ascii 20)
  }
)

(define-map estate-documents
  { estate-id: uint, document-type: (string-ascii 50) }
  {
    document-hash: (buff 32),
    uploaded-by: principal,
    uploaded-at: uint,
    is-verified: bool
  }
)

(define-map probate-timeline
  { estate-id: uint, milestone: (string-ascii 50) }
  {
    completed: bool,
    completed-at: (optional uint),
    notes: (string-ascii 200)
  }
)

;; Read-only functions
(define-read-only (get-executor-estate (estate-id uint))
  (map-get? executor-estates { estate-id: estate-id })
)

(define-read-only (get-executor-task (task-id uint))
  (map-get? executor-tasks { task-id: task-id })
)

(define-read-only (get-executor-compensation (estate-id uint) (executor principal))
  (map-get? executor-compensation { estate-id: estate-id, executor: executor })
)

(define-read-only (get-estate-document (estate-id uint) (document-type (string-ascii 50)))
  (map-get? estate-documents { estate-id: estate-id, document-type: document-type })
)

(define-read-only (get-probate-milestone (estate-id uint) (milestone (string-ascii 50)))
  (map-get? probate-timeline { estate-id: estate-id, milestone: milestone })
)

(define-read-only (get-counters)
  {
    estate-counter: (var-get estate-counter),
    task-counter: (var-get task-counter),
    executor-counter: (var-get executor-counter)
  }
)

(define-read-only (calculate-executor-fee (estate-value uint))
  (if (<= estate-value u100000)
    (/ (* estate-value u5) u100)
    (if (<= estate-value u500000)
      (+ u5000 (/ (* (- estate-value u100000) u4) u100))
      (if (<= estate-value u1000000)
        (+ u21000 (/ (* (- estate-value u500000) u3) u100))
        (+ u36000 (/ (* (- estate-value u1000000) u2) u100))
      )
    )
  )
)

;; Private functions
(define-private (is-authorized-executor (estate-id uint) (user principal))
  (match (get-executor-estate estate-id)
    estate-data
      (or (is-eq user (get primary-executor estate-data))
          (is-eq (some user) (get backup-executor estate-data)))
    false)
)

;; Public functions
(define-public (create-executor-estate (deceased-owner principal) (primary-executor principal) (backup-executor (optional principal)) (estate-value uint))
  (let ((estate-id (+ (var-get estate-counter) u1)))
    (asserts! (> estate-value u0) ERR-INVALID-INPUT)

    (map-set executor-estates
      { estate-id: estate-id }
      {
        deceased-owner: deceased-owner,
        primary-executor: primary-executor,
        backup-executor: backup-executor,
        estate-value: estate-value,
        probate-status: "pending",
        created-at: block-height,
        probate-started: none,
        probate-completed: none
      }
    )

    ;; Initialize executor compensation
    (map-set executor-compensation
      { estate-id: estate-id, executor: primary-executor }
      {
        base-fee: (calculate-executor-fee estate-value),
        hourly-rate: u150,
        hours-worked: u0,
        expenses-incurred: u0,
        total-compensation: u0,
        payment-status: "pending"
      }
    )

    ;; Initialize probate milestones
    (map-set probate-timeline { estate-id: estate-id, milestone: "inventory-assets" }
      { completed: false, completed-at: none, notes: "" })
    (map-set probate-timeline { estate-id: estate-id, milestone: "pay-debts" }
      { completed: false, completed-at: none, notes: "" })
    (map-set probate-timeline { estate-id: estate-id, milestone: "file-taxes" }
      { completed: false, completed-at: none, notes: "" })
    (map-set probate-timeline { estate-id: estate-id, milestone: "distribute-assets" }
      { completed: false, completed-at: none, notes: "" })

    (var-set estate-counter estate-id)
    (ok estate-id)
  )
)

(define-public (start-probate-process (estate-id uint))
  (let ((estate-data (unwrap! (get-executor-estate estate-id) ERR-ESTATE-NOT-FOUND)))
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get probate-status estate-data) "pending") ERR-NOT-AUTHORIZED)

    (map-set executor-estates
      { estate-id: estate-id }
      (merge estate-data {
        probate-status: "active",
        probate-started: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (create-executor-task (estate-id uint) (task-name (string-ascii 100)) (task-category (string-ascii 50)) (description (string-ascii 300)) (priority-level uint) (due-date (optional uint)))
  (let (
    (task-id (+ (var-get task-counter) u1))
    (estate-data (unwrap! (get-executor-estate estate-id) ERR-ESTATE-NOT-FOUND))
  )
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len task-name) u0) ERR-INVALID-INPUT)
    (asserts! (<= priority-level u5) ERR-INVALID-INPUT)

    (map-set executor-tasks
      { task-id: task-id }
      {
        estate-id: estate-id,
        task-name: task-name,
        task-category: task-category,
        description: description,
        priority-level: priority-level,
        due-date: due-date,
        assigned-to: tx-sender,
        status: "pending",
        created-at: block-height,
        completed-at: none
      }
    )

    (var-set task-counter task-id)
    (ok task-id)
  )
)

(define-public (complete-executor-task (task-id uint) (completion-notes (string-ascii 200)))
  (let ((task-data (unwrap! (get-executor-task task-id) ERR-TASK-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get assigned-to task-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status task-data) "pending") ERR-TASK-ALREADY-COMPLETED)

    (map-set executor-tasks
      { task-id: task-id }
      (merge task-data {
        status: "completed",
        completed-at: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (upload-estate-document (estate-id uint) (document-type (string-ascii 50)) (document-hash (buff 32)))
  (let ((estate-data (unwrap! (get-executor-estate estate-id) ERR-ESTATE-NOT-FOUND)))
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len document-type) u0) ERR-INVALID-INPUT)

    (map-set estate-documents
      { estate-id: estate-id, document-type: document-type }
      {
        document-hash: document-hash,
        uploaded-by: tx-sender,
        uploaded-at: block-height,
        is-verified: false
      }
    )

    (ok true)
  )
)

(define-public (verify-estate-document (estate-id uint) (document-type (string-ascii 50)))
  (let ((document-data (unwrap! (get-estate-document estate-id document-type) ERR-TASK-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set estate-documents
      { estate-id: estate-id, document-type: document-type }
      (merge document-data { is-verified: true })
    )

    (ok true)
  )
)

(define-public (update-probate-milestone (estate-id uint) (milestone (string-ascii 50)) (notes (string-ascii 200)))
  (let ((milestone-data (unwrap! (get-probate-milestone estate-id milestone) ERR-TASK-NOT-FOUND)))
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed milestone-data)) ERR-TASK-ALREADY-COMPLETED)

    (map-set probate-timeline
      { estate-id: estate-id, milestone: milestone }
      (merge milestone-data {
        completed: true,
        completed-at: (some block-height),
        notes: notes
      })
    )

    (ok true)
  )
)

(define-public (record-executor-hours (estate-id uint) (hours-worked uint) (expenses uint))
  (let (
    (compensation-data (unwrap! (get-executor-compensation estate-id tx-sender) ERR-EXECUTOR-NOT-FOUND))
    (estate-data (unwrap! (get-executor-estate estate-id) ERR-ESTATE-NOT-FOUND))
  )
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> hours-worked u0) ERR-INVALID-INPUT)

    (let (
      (new-total-hours (+ (get hours-worked compensation-data) hours-worked))
      (new-total-expenses (+ (get expenses-incurred compensation-data) expenses))
      (hourly-compensation (* hours-worked (get hourly-rate compensation-data)))
      (new-total-compensation (+ (+ (get base-fee compensation-data) hourly-compensation) new-total-expenses))
    )
      (map-set executor-compensation
        { estate-id: estate-id, executor: tx-sender }
        (merge compensation-data {
          hours-worked: new-total-hours,
          expenses-incurred: new-total-expenses,
          total-compensation: new-total-compensation
        })
      )
    )

    (ok true)
  )
)

(define-public (complete-probate-process (estate-id uint))
  (let ((estate-data (unwrap! (get-executor-estate estate-id) ERR-ESTATE-NOT-FOUND)))
    (asserts! (is-authorized-executor estate-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get probate-status estate-data) "active") ERR-NOT-AUTHORIZED)

    (map-set executor-estates
      { estate-id: estate-id }
      (merge estate-data {
        probate-status: "completed",
        probate-completed: (some block-height)
      })
    )

    (ok true)
  )
)
