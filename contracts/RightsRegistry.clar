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

;; Private Functions
(define-private (sanitize-song-id (id uint))
    (if (> id u0)
        id
        u0))

(define-private (sanitize-title (input (string-ascii 256)))
    (if (is-eq input "")
        "untitled"
        input))

(define-private (sanitize-status (input (string-ascii 10)))
    (if (or (is-eq input "active") (is-eq input "inactive"))
        input
        "inactive"))

(define-private (sanitize-role (input (string-ascii 20)))
    (if (or 
        (is-eq input "writer")
        (is-eq input "producer")
        (is-eq input "performer"))
        input
        "other"))

(define-private (validate-song-id (id uint))
    (if (> id u0)
        (ok id)
        ERR-INVALID-SONG-ID))

(define-private (validate-title (input (string-ascii 256)))
    (if (not (is-eq input ""))
        (ok input)
        ERR-INVALID-TITLE))

(define-private (validate-status (input (string-ascii 10)))
    (if (or (is-eq input "active") (is-eq input "inactive"))
        (ok input)
        ERR-INVALID-STATUS))

(define-private (validate-role (input (string-ascii 20)))
    (if (or 
        (is-eq input "writer")
        (is-eq input "producer")
        (is-eq input "performer"))
        (ok input)
        ERR-INVALID-ROLE))

(define-private (get-total-share (song-id uint))
    (get total-share 
        (default-to 
            { total-share: u0 }
            (map-get? total-song-shares { song-id: (sanitize-song-id song-id) }))))

;; Read-Only Functions
(define-read-only (get-song-details (song-id uint))
    (let
        ((safe-id (sanitize-song-id song-id)))
        (ok (map-get? rights-registry { song-id: safe-id }))))

(define-read-only (get-collaborator-share (song-id uint) (collaborator principal))
    (let
        ((safe-id (sanitize-song-id song-id)))
        (ok (map-get? royalty-splits 
            { song-id: safe-id, collaborator: collaborator }))))

;; Public Functions
(define-public (register-song (song-id uint) (title (string-ascii 256)))
    (let
        ((safe-id (sanitize-song-id song-id))
         (safe-title (sanitize-title title)))
        
        ;; Input validation
        (try! (validate-song-id safe-id))
        (try! (validate-title safe-title))
        
        ;; Authorization check
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        
        ;; Check if song already exists
        (asserts! (is-none (map-get? rights-registry { song-id: safe-id })) ERR-ALREADY-EXISTS)
        
        ;; Register the song
        (map-set rights-registry
            { song-id: safe-id }
            {
                owner: tx-sender,
                title: safe-title,
                created-at: block-height,
                status: "active"
            }
        )
        
        ;; Initialize total share
        (map-set total-song-shares
            { song-id: safe-id }
            { total-share: u0 }
        )
        
        (ok true)
    ))

(define-public (add-collaborator 
    (song-id uint) 
    (collaborator principal) 
    (share uint)
    (role (string-ascii 20)))
    (let
        ((safe-id (sanitize-song-id song-id))
         (safe-role (sanitize-role role)))
        
        ;; Input validation
        (try! (validate-song-id safe-id))
        (try! (validate-role safe-role))
        (asserts! (not (is-eq collaborator tx-sender)) ERR-ZERO-ADDRESS)
        (asserts! (<= share u10000) ERR-INVALID-SHARE)
        
        ;; Get song details and validate
        (let ((song-exists (map-get? rights-registry { song-id: safe-id }))
              (current-total (get-total-share safe-id)))
            
            (asserts! (is-some song-exists) ERR-INVALID-SONG)
            (asserts! (is-eq tx-sender (get owner (unwrap-panic song-exists))) ERR-NOT-AUTHORIZED)
            
            ;; Check if total share would exceed 100%
            (asserts! (<= (+ share current-total) u10000) ERR-TOTAL-SHARE-EXCEEDED)
            
            ;; Update collaborator share
            (map-set royalty-splits
                { song-id: safe-id, collaborator: collaborator }
                { share: share, role: safe-role }
            )
            
            ;; Update total share
            (map-set total-song-shares
                { song-id: safe-id }
                { total-share: (+ share current-total) }
            )
            
            (ok true)
        )))

(define-public (update-song-status (song-id uint) (new-status (string-ascii 10)))
    (let
        ((safe-id (sanitize-song-id song-id))
         (safe-status (sanitize-status new-status)))
        
        ;; Input validation
        (try! (validate-song-id safe-id))
        (try! (validate-status safe-status))
        
        (let ((song-exists (map-get? rights-registry { song-id: safe-id })))
            (asserts! (is-some song-exists) ERR-INVALID-SONG)
            (asserts! (is-eq tx-sender (get owner (unwrap-panic song-exists))) ERR-NOT-AUTHORIZED)
            
            (map-set rights-registry
                { song-id: safe-id }
                (merge (unwrap-panic song-exists) { status: safe-status })
            )
            (ok true)
        )))

;; Administrative Functions
(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-owner tx-sender)) ERR-ZERO-ADDRESS)
        (var-set contract-owner new-owner)
        (ok true)
    ))
