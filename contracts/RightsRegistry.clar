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

;; Error Constants
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

;; Constants for validation
(define-constant MIN-SONG-ID u1)
(define-constant MAX-SONG-ID u1000000)
(define-constant MIN-TITLE-LENGTH u1)
(define-constant MAX-TITLE-LENGTH u256)
(define-constant VALID-ROLES (list "writer" "producer" "performer"))
(define-constant VALID-STATUSES (list "active" "inactive"))

;; Data Variables
(define-data-var contract-owner principal tx-sender)

;; Data Maps
(define-map rights-registry
    { song-id: uint }
    {
        owner: principal,
        title: (string-ascii 256),
        created-at: uint,
        status: (string-ascii 10)
    }
)

(define-map royalty-splits
    { song-id: uint, collaborator: principal }
    { 
        share: uint,
        role: (string-ascii 20)
    }
)

(define-map total-song-shares
    { song-id: uint }
    { total-share: uint }
)

;; Private Helper Functions
(define-private (is-valid-song-id (id uint))
    (and 
        (>= id MIN-SONG-ID)
        (<= id MAX-SONG-ID)))

(define-private (is-valid-title (title (string-ascii 256)))
    (and 
        (>= (len title) MIN-TITLE-LENGTH)
        (<= (len title) MAX-TITLE-LENGTH)))

(define-private (is-valid-role (role (string-ascii 20)))
    (asserts! 
        (or 
            (is-eq role "writer")
            (is-eq role "producer")
            (is-eq role "performer"))
        ERR-INVALID-ROLE))

(define-private (is-valid-status (status (string-ascii 10)))
    (asserts! 
        (or 
            (is-eq status "active")
            (is-eq status "inactive"))
        ERR-INVALID-STATUS))

(define-private (check-authorization)
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED))

;; Read-Only Functions
(define-read-only (get-song-details (song-id uint))
    (begin
        (asserts! (is-valid-song-id song-id) ERR-INVALID-SONG-ID)
        (ok (map-get? rights-registry { song-id: song-id }))))

(define-read-only (get-collaborator-share (song-id uint) (collaborator principal))
    (begin
        (asserts! (is-valid-song-id song-id) ERR-INVALID-SONG-ID)
        (ok (map-get? royalty-splits { song-id: song-id, collaborator: collaborator }))))

;; Public Functions
(define-public (register-song (song-id uint) (title (string-ascii 256)))
    (begin
        ;; Validate inputs first
        (asserts! (is-valid-song-id song-id) ERR-INVALID-SONG-ID)
        (asserts! (is-valid-title title) ERR-INVALID-TITLE)

        ;; Check authorization
        (check-authorization)

        ;; Verify song doesn't exist
        (asserts! (is-none (map-get? rights-registry { song-id: song-id })) ERR-ALREADY-EXISTS)

        ;; Register song
        (map-set rights-registry
            { song-id: song-id }
            {
                owner: tx-sender,
                title: title,
                created-at: block-height,
                status: "active"
            })

        ;; Initialize shares
        (map-set total-song-shares
            { song-id: song-id }
            { total-share: u0 })

        (ok true)))

(define-public (add-collaborator 
    (song-id uint) 
    (collaborator principal) 
    (share uint)
    (role (string-ascii 20)))
    (begin
        ;; Validate all inputs first
        (asserts! (is-valid-song-id song-id) ERR-INVALID-SONG-ID)
        (try! (is-valid-role role))
        (asserts! (not (is-eq collaborator tx-sender)) ERR-ZERO-ADDRESS)
        (asserts! (<= share u10000) ERR-INVALID-SHARE)

        (let ((song-details (unwrap! (get-song-details song-id) ERR-INVALID-SONG))
              (current-shares (default-to { total-share: u0 } 
                             (map-get? total-song-shares { song-id: song-id }))))

            ;; Verify ownership
            (asserts! (is-eq tx-sender (get owner song-details)) ERR-NOT-AUTHORIZED)

            ;; Check total shares
            (asserts! (<= (+ share (get total-share current-shares)) u10000) 
                     ERR-TOTAL-SHARE-EXCEEDED)

            ;; Update collaborator
            (map-set royalty-splits
                { song-id: song-id, collaborator: collaborator }
                { share: share, role: role })

            ;; Update total shares
            (map-set total-song-shares
                { song-id: song-id }
                { total-share: (+ share (get total-share current-shares)) })

            (ok true))))

(define-public (update-song-status 
    (song-id uint) 
    (new-status (string-ascii 10)))
    (begin
        ;; Validate inputs first
        (asserts! (is-valid-song-id song-id) ERR-INVALID-SONG-ID)
        (try! (is-valid-status new-status))

        (let ((song-details (unwrap! (get-song-details song-id) ERR-INVALID-SONG)))
            ;; Verify ownership
            (asserts! (is-eq tx-sender (get owner song-details)) ERR-NOT-AUTHORIZED)

            ;; Update status
            (map-set rights-registry
                { song-id: song-id }
                (merge song-details { status: new-status }))

            (ok true))))

;; Administrative Functions
(define-public (transfer-ownership (new-owner principal))
    (begin
        (check-authorization)
        (asserts! (not (is-eq new-owner tx-sender)) ERR-ZERO-ADDRESS)
        (var-set contract-owner new-owner)
        (ok true)))
