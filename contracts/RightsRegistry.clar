;; Define SIP-010 trait
(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Constants for validation
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-SONG (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-SHARE (err u103))
(define-constant ERR-INVALID-SONG-ID (err u104))
(define-constant ERR-INVALID-TITLE (err u105))
(define-constant ERR-INVALID-STATUS (err u106))
(define-constant ERR-INVALID-ROLE (err u107))
(define-constant ERR-ZERO-ADDRESS (err u108))
(define-constant ERR-TOTAL-SHARE-EXCEEDED (err u109))

;; Data Variables
(define-data-var contract-owner principal tx-sender)

;; Data Maps
(define-map rights-registry
    { song-id: uint }
    {
        owner: principal,
        title: (string-ascii 256),
        created-at: uint,
        status: (string-ascii 10)  ;; "active" or "inactive"
    }
)

(define-map royalty-splits
    { song-id: uint, collaborator: principal }
    { 
        share: uint,          ;; Percentage * 100 (e.g., 2500 = 25%)
        role: (string-ascii 20)  ;; e.g., "writer", "producer", "performer"
    }
)

(define-map total-song-shares
    { song-id: uint }
    { total-share: uint }
)

;; Private Functions
(define-private (validate-song-id (song-id uint))
    (ok (asserts! (> song-id u0) ERR-INVALID-SONG-ID))
)

(define-private (validate-title (title (string-ascii 256)))
    (ok (asserts! (not (is-eq title "")) ERR-INVALID-TITLE))
)

(define-private (validate-status (status (string-ascii 10)))
    (ok (asserts! 
        (or (is-eq status "active") (is-eq status "inactive")) 
        ERR-INVALID-STATUS))
)

(define-private (validate-role (role (string-ascii 20)))
    (ok (asserts! 
        (or 
            (is-eq role "writer")
            (is-eq role "producer")
            (is-eq role "performer")
        ) 
        ERR-INVALID-ROLE))
)

(define-private (get-total-share (song-id uint))
    (default-to 
        { total-share: u0 }
        (map-get? total-song-shares { song-id: song-id }))
)

;; Read-Only Functions
(define-read-only (get-song-details (song-id uint))
    (begin
        (try! (validate-song-id song-id))
        (ok (map-get? rights-registry { song-id: song-id }))
    )
)

(define-read-only (get-collaborator-share (song-id uint) (collaborator principal))
    (begin
        (try! (validate-song-id song-id))
        (ok (map-get? royalty-splits { song-id: song-id, collaborator: collaborator }))
    )
)

;; Public Functions
(define-public (register-song (song-id uint) (title (string-ascii 256)))
    (begin
        ;; Input validation
        (try! (validate-song-id song-id))
        (try! (validate-title title))

        ;; Authorization check
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)

        ;; Check if song already exists
        (asserts! (is-none (map-get? rights-registry { song-id: song-id })) ERR-ALREADY-EXISTS)

        ;; Register the song
        (map-set rights-registry
            { song-id: song-id }
            {
                owner: tx-sender,
                title: title,
                created-at: block-height,
                status: "active"
            }
        )

        ;; Initialize total share
        (map-set total-song-shares
            { song-id: song-id }
            { total-share: u0 }
        )

        (ok true)
    )
)

(define-public (add-collaborator 
    (song-id uint) 
    (collaborator principal) 
    (share uint)
    (role (string-ascii 20)))
    (begin
        ;; Input validation
        (try! (validate-song-id song-id))
        (try! (validate-role role))
        (asserts! (not (is-eq collaborator tx-sender)) ERR-ZERO-ADDRESS)
        (asserts! (<= share u10000) ERR-INVALID-SHARE)

        ;; Get song details and validate
        (let ((song-exists (map-get? rights-registry { song-id: song-id }))
              (current-total (get total-share (get-total-share song-id))))

            (asserts! (is-some song-exists) ERR-INVALID-SONG)
            (asserts! (is-eq tx-sender (get owner (unwrap-panic song-exists))) ERR-NOT-AUTHORIZED)

            ;; Check if total share would exceed 100%
            (asserts! (<= (+ share current-total) u10000) ERR-TOTAL-SHARE-EXCEEDED)

            ;; Update collaborator share
            (map-set royalty-splits
                { song-id: song-id, collaborator: collaborator }
                { share: share, role: role }
            )

            ;; Update total share
            (map-set total-song-shares
                { song-id: song-id }
                { total-share: (+ share current-total) }
            )

            (ok true)
        )
    )
)

(define-public (update-song-status (song-id uint) (new-status (string-ascii 10)))
    (begin
        ;; Input validation
        (try! (validate-song-id song-id))
        (try! (validate-status new-status))

        (let ((song-exists (map-get? rights-registry { song-id: song-id })))
            (asserts! (is-some song-exists) ERR-INVALID-SONG)
            (asserts! (is-eq tx-sender (get owner (unwrap-panic song-exists))) ERR-NOT-AUTHORIZED)

            (map-set rights-registry
                { song-id: song-id }
                (merge (unwrap-panic song-exists) { status: new-status })
            )
            (ok true)
        )
    )
)

;; Administrative Functions
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-owner tx-sender)) ERR-ZERO-ADDRESS)
        (var-set contract-owner new-owner)
        (ok true)
    )
)
