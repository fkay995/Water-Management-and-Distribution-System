;; Billing and Consumption Contract
;; Manages water usage tracking, billing calculations, and payment processing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-AMOUNT (err u301))
(define-constant ERR-INSUFFICIENT-BALANCE (err u302))
(define-constant ERR-ACCOUNT-NOT-FOUND (err u303))
(define-constant ERR-METER-NOT-FOUND (err u304))
(define-constant ERR-INVALID-READING (err u305))
(define-constant ERR-PAYMENT-FAILED (err u306))
(define-constant ERR-ALREADY-PAID (err u307))
(define-constant ERR-OVERDUE-PAYMENT (err u308))

;; Pricing tiers (per 1000 liters)
(define-constant TIER-1-LIMIT u50000) ;; 50,000 liters
(define-constant TIER-2-LIMIT u100000) ;; 100,000 liters
(define-constant TIER-3-LIMIT u200000) ;; 200,000 liters

(define-constant TIER-1-PRICE u100) ;; 1.00 STX per 1000L
(define-constant TIER-2-PRICE u150) ;; 1.50 STX per 1000L
(define-constant TIER-3-PRICE u200) ;; 2.00 STX per 1000L
(define-constant TIER-4-PRICE u300) ;; 3.00 STX per 1000L

;; Late payment penalty
(define-constant LATE-PAYMENT-PENALTY u10) ;; 10% penalty

;; Data structures
(define-map customer-accounts
  { customer: principal }
  {
    account-id: (string-ascii 20),
    name: (string-ascii 100),
    address: (string-ascii 200),
    account-balance: int, ;; can be negative for credits
    total-consumption: uint,
    last-payment: uint,
    payment-due-date: uint,
    account-status: (string-ascii 20), ;; active, suspended, disconnected
    created-at: uint
  }
)

(define-map water-meters
  { meter-id: (string-ascii 20) }
  {
    customer: principal,
    location: (string-ascii 100),
    meter-type: (string-ascii 20),
    current-reading: uint,
    last-reading: uint,
    last-reading-date: uint,
    installation-date: uint,
    active: bool
  }
)

(define-map consumption-records
  { record-id: uint }
  {
    customer: principal,
    meter-id: (string-ascii 20),
    reading-date: uint,
    current-reading: uint,
    previous-reading: uint,
    consumption-amount: uint,
    billing-period: (string-ascii 20),
    recorded-by: principal
  }
)

(define-map billing-invoices
  { invoice-id: uint }
  {
    customer: principal,
    billing-period: (string-ascii 20),
    consumption-amount: uint,
    tier-1-usage: uint,
    tier-2-usage: uint,
    tier-3-usage: uint,
    tier-4-usage: uint,
    base-amount: uint,
    penalties: uint,
    total-amount: uint,
    due-date: uint,
    paid: bool,
    paid-date: uint,
    generated-at: uint
  }
)

(define-map payments
  { payment-id: uint }
  {
    customer: principal,
    invoice-id: uint,
    amount: uint,
    payment-method: (string-ascii 20),
    payment-date: uint,
    transaction-hash: (string-ascii 64)
  }
)

(define-map authorized-readers principal bool)

;; Data variables
(define-data-var next-record-id uint u1)
(define-data-var next-invoice-id uint u1)
(define-data-var next-payment-id uint u1)
(define-data-var total-revenue uint u0)
(define-data-var total-customers uint u0)

;; Authorization functions
(define-public (authorize-meter-reader (reader principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-readers reader true))
  )
)

(define-public (revoke-meter-reader (reader principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-readers reader))
  )
)

(define-read-only (is-authorized-reader (reader principal))
  (default-to false (map-get? authorized-readers reader))
)

;; Account management
(define-public (create-customer-account
  (customer principal)
  (account-id (string-ascii 20))
  (name (string-ascii 100))
  (address (string-ascii 200))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? customer-accounts { customer: customer })) ERR-ACCOUNT-NOT-FOUND)

    (map-set customer-accounts
      { customer: customer }
      {
        account-id: account-id,
        name: name,
        address: address,
        account-balance: 0,
        total-consumption: u0,
        last-payment: u0,
        payment-due-date: u0,
        account-status: "active",
        created-at: block-height
      }
    )
    (var-set total-customers (+ (var-get total-customers) u1))
    (ok customer)
  )
)

(define-public (install-water-meter
  (meter-id (string-ascii 20))
  (customer principal)
  (location (string-ascii 100))
  (meter-type (string-ascii 20))
  (initial-reading uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? customer-accounts { customer: customer })) ERR-ACCOUNT-NOT-FOUND)

    (map-set water-meters
      { meter-id: meter-id }
      {
        customer: customer,
        location: location,
        meter-type: meter-type,
        current-reading: initial-reading,
        last-reading: initial-reading,
        last-reading-date: block-height,
        installation-date: block-height,
        active: true
      }
    )
    (ok meter-id)
  )
)

;; Consumption tracking
(define-public (record-meter-reading
  (meter-id (string-ascii 20))
  (new-reading uint)
  (billing-period (string-ascii 20))
)
  (let (
    (meter (unwrap! (map-get? water-meters { meter-id: meter-id }) ERR-METER-NOT-FOUND))
    (record-id (var-get next-record-id))
  )
    (asserts! (is-authorized-reader tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active meter) ERR-METER-NOT-FOUND)
    (asserts! (>= new-reading (get current-reading meter)) ERR-INVALID-READING)

    (let ((consumption (- new-reading (get current-reading meter))))
      (map-set consumption-records
        { record-id: record-id }
        {
          customer: (get customer meter),
          meter-id: meter-id,
          reading-date: block-height,
          current-reading: new-reading,
          previous-reading: (get current-reading meter),
          consumption-amount: consumption,
          billing-period: billing-period,
          recorded-by: tx-sender
        }
      )

      (map-set water-meters
        { meter-id: meter-id }
        (merge meter {
          current-reading: new-reading,
          last-reading: (get current-reading meter),
          last-reading-date: block-height
        })
      )

      (update-customer-consumption (get customer meter) consumption)
      (var-set next-record-id (+ record-id u1))
      (ok record-id)
    )
  )
)

;; Update customer total consumption
(define-private (update-customer-consumption (customer principal) (consumption uint))
  (let ((account (unwrap-panic (map-get? customer-accounts { customer: customer }))))
    (map-set customer-accounts
      { customer: customer }
      (merge account { total-consumption: (+ (get total-consumption account) consumption) })
    )
  )
)

;; Billing calculations
(define-public (generate-invoice
  (customer principal)
  (billing-period (string-ascii 20))
  (consumption-amount uint)
)
  (let (
    (invoice-id (var-get next-invoice-id))
    (account (unwrap! (map-get? customer-accounts { customer: customer }) ERR-ACCOUNT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (let ((tier-breakdown (calculate-tiered-pricing consumption-amount)))
      (let (
        (base-amount (get total-cost tier-breakdown))
        (penalties (calculate-penalties customer))
        (total-amount (+ base-amount penalties))
      )
        (map-set billing-invoices
          { invoice-id: invoice-id }
          {
            customer: customer,
            billing-period: billing-period,
            consumption-amount: consumption-amount,
            tier-1-usage: (get tier-1 tier-breakdown),
            tier-2-usage: (get tier-2 tier-breakdown),
            tier-3-usage: (get tier-3 tier-breakdown),
            tier-4-usage: (get tier-4 tier-breakdown),
            base-amount: base-amount,
            penalties: penalties,
            total-amount: total-amount,
            due-date: (+ block-height u30), ;; 30 blocks due date
            paid: false,
            paid-date: u0,
            generated-at: block-height
          }
        )

        (update-account-balance customer (to-int total-amount))
        (var-set next-invoice-id (+ invoice-id u1))
        (ok invoice-id)
      )
    )
  )
)

;; Calculate tiered pricing
(define-private (calculate-tiered-pricing (consumption uint))
  (let (
    (tier-1 (if (<= consumption TIER-1-LIMIT) consumption TIER-1-LIMIT))
    (remaining-1 (if (> consumption TIER-1-LIMIT) (- consumption TIER-1-LIMIT) u0))
    (tier-2 (if (<= remaining-1 (- TIER-2-LIMIT TIER-1-LIMIT)) remaining-1 (- TIER-2-LIMIT TIER-1-LIMIT)))
    (remaining-2 (if (> remaining-1 (- TIER-2-LIMIT TIER-1-LIMIT)) (- remaining-1 (- TIER-2-LIMIT TIER-1-LIMIT)) u0))
    (tier-3 (if (<= remaining-2 (- TIER-3-LIMIT TIER-2-LIMIT)) remaining-2 (- TIER-3-LIMIT TIER-2-LIMIT)))
    (tier-4 (if (> remaining-2 (- TIER-3-LIMIT TIER-2-LIMIT)) (- remaining-2 (- TIER-3-LIMIT TIER-2-LIMIT)) u0))
  )
    {
      tier-1: tier-1,
      tier-2: tier-2,
      tier-3: tier-3,
      tier-4: tier-4,
      total-cost: (+
        (/ (* tier-1 TIER-1-PRICE) u1000)
        (/ (* tier-2 TIER-2-PRICE) u1000)
        (/ (* tier-3 TIER-3-PRICE) u1000)
        (/ (* tier-4 TIER-4-PRICE) u1000)
      )
    }
  )
)

;; Calculate late payment penalties
(define-private (calculate-penalties (customer principal))
  (let ((account (unwrap-panic (map-get? customer-accounts { customer: customer }))))
    (if (and (> (get payment-due-date account) u0) (> block-height (get payment-due-date account)))
      (/ (* (to-uint (get account-balance account)) LATE-PAYMENT-PENALTY) u100)
      u0
    )
  )
)

;; Payment processing
(define-public (process-payment (invoice-id uint) (amount uint))
  (let (
    (invoice (unwrap! (map-get? billing-invoices { invoice-id: invoice-id }) ERR-ACCOUNT-NOT-FOUND))
    (payment-id (var-get next-payment-id))
  )
    (asserts! (is-eq tx-sender (get customer invoice)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get paid invoice)) ERR-ALREADY-PAID)
    (asserts! (>= amount (get total-amount invoice)) ERR-INSUFFICIENT-BALANCE)

    ;; Process STX payment (simplified - in practice would use stx-transfer?)
    (map-set payments
      { payment-id: payment-id }
      {
        customer: (get customer invoice),
        invoice-id: invoice-id,
        amount: amount,
        payment-method: "STX",
        payment-date: block-height,
        transaction-hash: "simulated-hash"
      }
    )

    (map-set billing-invoices
      { invoice-id: invoice-id }
      (merge invoice { paid: true, paid-date: block-height })
    )

    (update-account-balance (get customer invoice) (- (to-int amount)))
    (var-set next-payment-id (+ payment-id u1))
    (var-set total-revenue (+ (var-get total-revenue) amount))
    (ok payment-id)
  )
)

;; Update account balance
(define-private (update-account-balance (customer principal) (amount int))
  (let ((account (unwrap-panic (map-get? customer-accounts { customer: customer }))))
    (map-set customer-accounts
      { customer: customer }
      (merge account {
        account-balance: (+ (get account-balance account) amount),
        last-payment: (if (< amount 0) block-height (get last-payment account))
      })
    )
  )
)

;; Read-only functions
(define-read-only (get-customer-account (customer principal))
  (map-get? customer-accounts { customer: customer })
)

(define-read-only (get-water-meter (meter-id (string-ascii 20)))
  (map-get? water-meters { meter-id: meter-id })
)

(define-read-only (get-consumption-record (record-id uint))
  (map-get? consumption-records { record-id: record-id })
)

(define-read-only (get-invoice (invoice-id uint))
  (map-get? billing-invoices { invoice-id: invoice-id })
)

(define-read-only (get-payment (payment-id uint))
  (map-get? payments { payment-id: payment-id })
)

(define-read-only (get-total-revenue)
  (var-get total-revenue)
)

(define-read-only (get-total-customers)
  (var-get total-customers)
)

;; Initialize contract
(begin
  (map-set authorized-readers CONTRACT-OWNER true)
)
