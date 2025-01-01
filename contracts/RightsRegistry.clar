;; Rights Registry Contract
;; Handles music rights ownership, royalty splits, and rights transfers

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
