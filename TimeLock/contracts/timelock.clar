;; Time Lock - Production-Ready STX Time-Locked Asset Management
;; Advanced time-locked vaults with vesting, multi-beneficiary support, and conditions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-params (err u101))
(define-constant err-lock-not-found (err u102))
(define-constant err-already-claimed (err u103))
(define-constant err-not-unlocked (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-beneficiary (err u106))
(define-constant err-lock-cancelled (err u107))
(define-constant err-past-deadline (err u108))
(define-constant err-invalid-schedule (err u109))
(define-constant err-exceeds-limit (err u110))

;; Data Variables
(define-data-var next-lock-id uint u0)
(define-data-var total-locked uint u0)
(define-data-var protocol-fee uint u25) ;; 0.25% in basis points
(define-data-var emergency-pause bool false)
(define-data-var max-beneficiaries uint u10)
(define-data-var treasury principal contract-owner)

;; Data Maps
(define-map locks uint {
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
})

(define-map lock-beneficiaries uint (list 10 {
  beneficiary: principal,
  percentage: uint,
  claimed: uint,
  can-cancel: bool
}))

(define-map vesting-claims {lock-id: uint, release-number: uint} bool)
(define-map beneficiary-locks principal (list 100 uint))
(define-map creator-locks principal (list 100 uint))

;; Read-only functions
(define-read-only (get-lock (lock-id uint))
  (map-get? locks lock-id)
)

(define-read-only (get-lock-beneficiaries (lock-id uint))
  (default-to (list) (map-get? lock-beneficiaries lock-id))
)

(define-read-only (get-next-lock-id)
  (var-get next-lock-id)
)

(define-read-only (get-total-locked)
  (var-get total-locked)
)

(define-read-only (calculate-vesting-amount (lock-id uint) (beneficiary principal))
  (match (map-get? locks lock-id)
    lock-info
    (let ((beneficiaries (get-lock-beneficiaries lock-id))
          (current-height burn-block-height)
          (unlock-height (get unlock-height lock-info))
          (vesting-period (get vesting-period lock-info))
          (total-releases (get vesting-releases lock-info))
          (time-passed (- current-height unlock-height)))
      (if (get is-vesting lock-info)
        (let ((releases-available (/ time-passed vesting-period))
              (clamped-releases (if (> releases-available total-releases) 
                                   total-releases 
                                   releases-available)))
          (fold calculate-beneficiary-vesting beneficiaries 
            {
              target: beneficiary,
              lock-id: lock-id,
              amount: (get amount lock-info),
              releases: clamped-releases,
              total-releases: total-releases,
              available: u0
            }
          )
        )
        {target: beneficiary, lock-id: lock-id, amount: u0, releases: u0, total-releases: u0, available: u0}
      )
    )
    {target: beneficiary, lock-id: lock-id, amount: u0, releases: u0, total-releases: u0, available: u0}
  )
)

(define-read-only (is-unlocked (lock-id uint))
  (match (map-get? locks lock-id)
    lock-info
    (let ((unlock-height (get unlock-height lock-info))
          (condition-type (get condition-type lock-info)))
      (if (is-eq condition-type "none")
        (>= burn-block-height unlock-height)
        (and (>= burn-block-height unlock-height)
             (check-condition condition-type (get condition-value lock-info)))
      )
    )
    false
  )
)

;; Private functions
(define-private (calculate-beneficiary-vesting (beneficiary-info {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool}) 
                                               (context {target: principal, lock-id: uint, amount: uint, releases: uint, total-releases: uint, available: uint}))
  (if (is-eq (get beneficiary beneficiary-info) (get target context))
    (let ((total-share (/ (* (get amount context) (get percentage beneficiary-info)) u10000))
          (per-release (/ total-share (get total-releases context)))
          (total-available (* per-release (get releases context)))
          (net-available (- total-available (get claimed beneficiary-info))))
      (merge context {available: net-available})
    )
    context
  )
)

(define-private (check-condition (condition-type (string-ascii 20)) (condition-value uint))
  (if (is-eq condition-type "price-above")
    true ;; Would integrate with price oracle
    (if (is-eq condition-type "block-reached")
      (>= burn-block-height condition-value)
      true
    )
  )
)

(define-private (validate-beneficiaries (beneficiaries (list 10 {beneficiary: principal, percentage: uint, can-cancel: bool})))
  (let ((total-percentage (fold add-percentage beneficiaries u0)))
    (and (is-eq total-percentage u10000)
         (> (len beneficiaries) u0)
         (<= (len beneficiaries) (var-get max-beneficiaries)))
  )
)

(define-private (add-percentage (entry {beneficiary: principal, percentage: uint, can-cancel: bool}) (total uint))
  (+ (get percentage entry) total)
)

(define-private (add-to-beneficiary-list (beneficiary-info {beneficiary: principal, percentage: uint, can-cancel: bool}) (lock-id uint))
  (let ((beneficiary (get beneficiary beneficiary-info))
        (current-locks (default-to (list) (map-get? beneficiary-locks beneficiary))))
    (match (as-max-len? (append current-locks lock-id) u100)
      updated-list 
      (begin
        (map-set beneficiary-locks beneficiary updated-list)
        lock-id
      )
      lock-id ;; Return lock-id even if list update fails
    )
  )
)

(define-private (process-beneficiary-claim (beneficiary-info {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool})
                                          (context {claimer: principal, lock-info: {creator: principal, amount: uint, unlock-height: uint, created-height: uint, is-cancelled: bool, is-vesting: bool, vesting-period: uint, vesting-releases: uint, condition-type: (string-ascii 20), condition-value: uint}, total-claimed: uint, updated-list: (list 10 {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool})}))
  (if (is-eq (get beneficiary beneficiary-info) (get claimer context))
    (let ((share (/ (* (get amount (get lock-info context)) (get percentage beneficiary-info)) u10000))
          (fee (/ (* share (var-get protocol-fee)) u10000))
          (net-amount (- share fee)))
      (merge context {
        total-claimed: (+ (get total-claimed context) net-amount),
        updated-list: (unwrap! (as-max-len? (append (get updated-list context) 
          (merge beneficiary-info {claimed: share})) u10) context)
      })
    )
    (merge context {
      updated-list: (unwrap! (as-max-len? (append (get updated-list context) beneficiary-info) u10) context)
    })
  )
)

;; Public functions
(define-public (create-lock (amount uint) (unlock-height uint) (beneficiaries (list 10 {beneficiary: principal, percentage: uint, can-cancel: bool})))
  (let ((lock-id (var-get next-lock-id)))
    (asserts! (not (var-get emergency-pause)) err-unauthorized)
    (asserts! (> amount u0) err-invalid-params)
    (asserts! (> unlock-height burn-block-height) err-invalid-params)
    (asserts! (validate-beneficiaries beneficiaries) err-invalid-params)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Create lock
    (map-set locks lock-id {
      creator: tx-sender,
      amount: amount,
      unlock-height: unlock-height,
      created-height: burn-block-height,
      is-cancelled: false,
      is-vesting: false,
      vesting-period: u0,
      vesting-releases: u0,
      condition-type: "none",
      condition-value: u0
    })
    
    ;; Set beneficiaries with initial claimed amount of 0
    (map-set lock-beneficiaries lock-id 
      (map add-claimed-field beneficiaries))
    
    ;; Update beneficiary lists - Fixed the fold call
    (fold add-to-beneficiary-list beneficiaries lock-id)
    
    ;; Update creator list
    (let ((creator-list (default-to (list) (map-get? creator-locks tx-sender))))
      (map-set creator-locks tx-sender 
        (unwrap! (as-max-len? (append creator-list lock-id) u100) err-exceeds-limit)))
    
    ;; Update global state
    (var-set next-lock-id (+ lock-id u1))
    (var-set total-locked (+ (var-get total-locked) amount))
    
    (ok lock-id)
  )
)

(define-public (create-vesting-lock (amount uint) (unlock-height uint) (vesting-period uint) (releases uint) (beneficiaries (list 10 {beneficiary: principal, percentage: uint, can-cancel: bool})))
  (let ((lock-id (var-get next-lock-id)))
    (asserts! (not (var-get emergency-pause)) err-unauthorized)
    (asserts! (> amount u0) err-invalid-params)
    (asserts! (> unlock-height burn-block-height) err-invalid-params)
    (asserts! (> vesting-period u0) err-invalid-params)
    (asserts! (> releases u0) err-invalid-params)
    (asserts! (validate-beneficiaries beneficiaries) err-invalid-params)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Create vesting lock
    (map-set locks lock-id {
      creator: tx-sender,
      amount: amount,
      unlock-height: unlock-height,
      created-height: burn-block-height,
      is-cancelled: false,
      is-vesting: true,
      vesting-period: vesting-period,
      vesting-releases: releases,
      condition-type: "none",
      condition-value: u0
    })
    
    ;; Set beneficiaries
    (map-set lock-beneficiaries lock-id 
      (map add-claimed-field beneficiaries))
    
    ;; Update beneficiary lists - Fixed the fold call
    (fold add-to-beneficiary-list beneficiaries lock-id)
    
    ;; Update creator list
    (let ((creator-list (default-to (list) (map-get? creator-locks tx-sender))))
      (map-set creator-locks tx-sender 
        (unwrap! (as-max-len? (append creator-list lock-id) u100) err-exceeds-limit)))
    
    ;; Update global state
    (var-set next-lock-id (+ lock-id u1))
    (var-set total-locked (+ (var-get total-locked) amount))
    
    (ok lock-id)
  )
)

(define-private (update-beneficiary-claimed (beneficiary-info {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool}) 
                                           (context {target: principal, amount: uint, updated: (list 10 {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool})}))
  (let ((updated-entry (if (is-eq (get beneficiary beneficiary-info) (get target context))
                          (merge beneficiary-info {claimed: (+ (get claimed beneficiary-info) (get amount context))})
                          beneficiary-info)))
    (merge context {
      updated: (unwrap! (as-max-len? (append (get updated context) updated-entry) u10) context)
    })
  )
)

(define-public (claim (lock-id uint))
  (match (map-get? locks lock-id)
    lock-info
    (begin
      (asserts! (not (get is-cancelled lock-info)) err-lock-cancelled)
      (asserts! (is-unlocked lock-id) err-not-unlocked)
      
      (if (get is-vesting lock-info)
        (claim-vesting lock-id)
        (claim-standard lock-id)
      )
    )
    err-lock-not-found
  )
)

(define-private (claim-standard (lock-id uint))
  (match (map-get? locks lock-id)
    lock-info
    (let ((beneficiaries (get-lock-beneficiaries lock-id))
          (result (fold process-beneficiary-claim beneficiaries 
            {claimer: tx-sender, lock-info: lock-info, total-claimed: u0, updated-list: (list)})))
      
      (asserts! (> (get total-claimed result) u0) err-invalid-beneficiary)
      
      ;; Update beneficiaries list
      (map-set lock-beneficiaries lock-id (get updated-list result))
      
      ;; Transfer STX
      (try! (as-contract (stx-transfer? (get total-claimed result) tx-sender tx-sender)))
      
      ;; Transfer fees
      (let ((total-fees (- (fold add-claimed (get updated-list result) u0) (get total-claimed result))))
        (if (> total-fees u0)
          (try! (as-contract (stx-transfer? total-fees tx-sender (var-get treasury))))
          true
        )
      )
      
      ;; Update total locked
      (var-set total-locked (- (var-get total-locked) (fold add-claimed (get updated-list result) u0)))
      
      (ok (get total-claimed result))
    )
    err-lock-not-found
  )
)

(define-private (claim-vesting (lock-id uint))
  (let ((vesting-info (calculate-vesting-amount lock-id tx-sender)))
    (asserts! (> (get available vesting-info) u0) err-invalid-beneficiary)
    
    ;; Update claimed amount for beneficiary
    (let ((beneficiaries (get-lock-beneficiaries lock-id))
          (update-context {target: tx-sender, amount: (get available vesting-info), updated: (list)})
          (result (fold update-beneficiary-claimed beneficiaries update-context))
          (updated-beneficiaries (get updated result)))
      
      (map-set lock-beneficiaries lock-id updated-beneficiaries)
      
      ;; Calculate and transfer fees
      (let ((fee (/ (* (get available vesting-info) (var-get protocol-fee)) u10000))
            (net-amount (- (get available vesting-info) fee)))
        
        ;; Transfer to beneficiary
        (try! (as-contract (stx-transfer? net-amount tx-sender tx-sender)))
        
        ;; Transfer fee
        (if (> fee u0)
          (try! (as-contract (stx-transfer? fee tx-sender (var-get treasury))))
          true
        )
        
        ;; Update total locked
        (var-set total-locked (- (var-get total-locked) (get available vesting-info)))
        
        (ok net-amount)
      )
    )
  )
)

(define-public (cancel-lock (lock-id uint))
  (match (map-get? locks lock-id)
    lock-info
    (let ((beneficiaries (get-lock-beneficiaries lock-id)))
      (asserts! (not (get is-cancelled lock-info)) err-lock-cancelled)
      (asserts! (can-cancel tx-sender lock-info beneficiaries) err-unauthorized)
      
      ;; Mark as cancelled
      (map-set locks lock-id (merge lock-info {is-cancelled: true}))
      
      ;; Calculate refund
      (let ((total-claimed (fold add-claimed beneficiaries u0))
            (refund-amount (- (get amount lock-info) total-claimed)))
        
        (if (> refund-amount u0)
          (begin
            ;; Refund to creator
            (try! (as-contract (stx-transfer? refund-amount tx-sender (get creator lock-info))))
            
            ;; Update total locked
            (var-set total-locked (- (var-get total-locked) refund-amount))
            
            (ok refund-amount)
          )
          (ok u0)
        )
      )
    )
    err-lock-not-found
  )
)

;; Helper functions
(define-private (add-claimed-field (beneficiary-info {beneficiary: principal, percentage: uint, can-cancel: bool}))
  (merge beneficiary-info {claimed: u0})
)

(define-private (add-claimed (beneficiary-info {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool}) (total uint))
  (+ (get claimed beneficiary-info) total)
)

(define-private (can-cancel (user principal) (lock-info {creator: principal, amount: uint, unlock-height: uint, created-height: uint, is-cancelled: bool, is-vesting: bool, vesting-period: uint, vesting-releases: uint, condition-type: (string-ascii 20), condition-value: uint}) (beneficiaries (list 10 {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool})))
  (let ((check-result (fold check-can-cancel beneficiaries {user: user, can: false})))
    (or (is-eq user (get creator lock-info))
        (get can check-result))
  )
)

(define-private (check-can-cancel (beneficiary-info {beneficiary: principal, percentage: uint, claimed: uint, can-cancel: bool}) 
                                 (context {user: principal, can: bool}))
  (if (and (is-eq (get beneficiary beneficiary-info) (get user context))
           (get can-cancel beneficiary-info))
    (merge context {can: true})
    context
  )
)

;; Admin functions
(define-public (set-protocol-fee (fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= fee u1000) err-invalid-params) ;; Max 10%
    (var-set protocol-fee fee)
    (ok fee)
  )
)

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (var-set treasury new-treasury)
    (ok new-treasury)
  )
)

(define-public (set-emergency-pause (paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (var-set emergency-pause paused)
    (ok paused)
  )
)