;; Rights Registry Contract
;; Handles music rights ownership, royalty splits, and rights transfers

(use-trait ft-trait .sip-010-trait.sip-010-trait)

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

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-SONG (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-SHARE (err u103))

;; Read-Only Functions
(define-read-only (get-song-details (song-id uint))
    (map-get? rights-registry { song-id: song-id })
)

(define-read-only (get-collaborator-share (song-id uint) (collaborator principal))
    (map-get? royalty-splits { song-id: song-id, collaborator: collaborator })
)
