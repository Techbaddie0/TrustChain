;; TrustChain Identity Verification Smart Contract

;; Constants
(define-constant admin-address tx-sender)
(define-constant VERIFICATION-NONE "none")
(define-constant VERIFICATION-PENDING "pending")
(define-constant VERIFICATION-CONFIRMED "confirmed")
(define-constant VERIFICATION-DENIED "denied")
(define-constant VERIFICATION-LAPSED "lapsed")
(define-constant blank-value "")

;; Additional error codes for data validation
(define-constant error-unauthorized (err u100))
(define-constant error-duplicate-registration (err u101))
(define-constant error-unregistered (err u102))
(define-constant error-invalid-verification-state (err u103))
(define-constant error-lapsed (err u104))
(define-constant error-data-invalid (err u105))
(define-constant error-restricted (err u106))
(define-constant error-invalid-charge (err u107))
(define-constant error-invalid-reputation (err u108))
(define-constant error-invalid-tier (err u109))
(define-constant error-empty-title (err u110))
(define-constant error-empty-criteria (err u111))
(define-constant error-invalid-minimum (err u112))
(define-constant error-null-address (err u113))
(define-constant error-self-attestation (err u114))

;; Validation constants
(define-constant MAX-REPUTATION-POINTS u100)
(define-constant MIN-REPUTATION-POINTS u0)
(define-constant MAX-CONSENSUS-THRESHOLD u100)
(define-constant MAX-SERVICE-CHARGE u1000000000) ;; 1000 STX
(define-constant MIN-SERVICE-CHARGE u100000)     ;; 0.1 STX
(define-constant MAX-IDENTITY-TIER u5)           ;; Maximum identity verification tier allowed

;; Data Maps
(define-map identities principal 
  { 
    verification-status: (string-utf8 20),
    credential-hash: (buff 32),
    creation-time: uint,
    valid-until: uint,
    attester: (optional principal),
    tier: uint,
    additional-info: (optional (string-utf8 256))
  }
)

(define-map authorized-attesters principal 
  {
    enabled: bool,
    attestation-count: uint,
    reputation-score: uint,
    registration-time: uint
  }
)

(define-map restricted-identities principal bool)

(define-map verification-tiers uint 
  {
    title: (string-utf8 50),
    criteria: (string-utf8 256),
    consensus-threshold: uint
  }
)

;; Data Variables
(define-data-var identity-count uint u0)
(define-data-var attester-count uint u0)
(define-data-var service-charge uint u1000000)

;; Validation helper functions
(define-private (is-valid-status (status (string-ascii 20)))
    (or 
        (is-eq status VERIFICATION-NONE)
        (is-eq status VERIFICATION-PENDING)
        (is-eq status VERIFICATION-CONFIRMED)
        (is-eq status VERIFICATION-DENIED)
        (is-eq status VERIFICATION-LAPSED)))

(define-private (is-valid-reputation (score uint))
    (and 
        (>= score MIN-REPUTATION-POINTS)
        (<= score MAX-REPUTATION-POINTS)))

(define-private (is-valid-charge (charge uint))
    (and 
        (>= charge MIN-SERVICE-CHARGE)
        (<= charge MAX-SERVICE-CHARGE)))

(define-private (is-valid-tier (tier uint))
    (<= tier MAX-IDENTITY-TIER))

(define-private (is-valid-threshold (threshold uint))
    (<= threshold MAX-CONSENSUS-THRESHOLD))

(define-private (is-valid-address (address principal))
    (and
        (not (is-eq address admin-address))
        (not (is-eq address tx-sender))))

;; Enhanced private functions
(define-private (is-authorized-attester (attester principal))
    (match (map-get? authorized-attesters attester)
        attester-data (and 
                    (get enabled attester-data)
                    (not (is-eq attester tx-sender)))  ;; Prevent self-attestation
        false))

(define-private (is-lapsed (identity principal))
    (match (map-get? identities identity)
        identity-data (> block-height (get valid-until identity-data))
        false))

(define-private (increment-attestation-count (attester principal))
    (match (map-get? authorized-attesters attester)
        attester-data 
            (map-set authorized-attesters 
                attester
                (merge attester-data { attestation-count: (+ (get attestation-count attester-data) u1) }))
        false))

;; Enhanced admin functions
(define-public (update-service-charge (new-charge uint))
    (begin
        (asserts! (is-eq tx-sender admin-address) error-unauthorized)
        (asserts! (is-valid-charge new-charge) error-invalid-charge)
        (ok (var-set service-charge new-charge))))

(define-public (register-attester (attester principal))
    (begin
        (asserts! (is-eq tx-sender admin-address) error-unauthorized)
        (asserts! (is-valid-address attester) error-null-address)
        (asserts! (not (is-authorized-attester attester)) error-duplicate-registration)
        (var-set attester-count (+ (var-get attester-count) u1))
        (ok
            (map-set authorized-attesters attester
                {
                    enabled: true,
                    attestation-count: u0,
                    reputation-score: u100,
                    registration-time: block-height
                }))))

(define-public (update-attester-reputation (attester principal) (new-score uint))
    (begin
        (asserts! (is-eq tx-sender admin-address) error-unauthorized)
        (asserts! (is-valid-reputation new-score) error-invalid-reputation)
        (asserts! (is-authorized-attester attester) error-unregistered)
        (match (map-get? authorized-attesters attester)
            attester-data
                (ok
                    (map-set authorized-attesters attester
                        (merge attester-data { reputation-score: new-score })))
            error-unregistered)))

(define-private (is-empty-string (str (string-utf8 256)))
    (is-eq (len str) u0))

;; Fixed add-verification-tier function with proper string validation
(define-public (add-verification-tier (tier uint) (title (string-utf8 50)) (criteria (string-utf8 256)) (consensus-threshold uint))
    (begin
        ;; Validate authorization
        (asserts! (is-eq tx-sender admin-address) error-unauthorized)

        ;; Validate tier
        (asserts! (is-valid-tier tier) error-invalid-tier)

        ;; Validate strings using length check
        (asserts! (not (is-empty-string title)) error-empty-title)
        (asserts! (not (is-empty-string criteria)) error-empty-criteria)

        ;; Validate threshold
        (asserts! (is-valid-threshold consensus-threshold) error-invalid-minimum)

        ;; If all validations pass, set the verification tier
        (ok
            (map-set verification-tiers tier
                {
                    title: title,
                    criteria: criteria,
                    consensus-threshold: consensus-threshold
                }))))

;; Read-only function to check if a tier exists
(define-read-only (verification-tier-exists (tier uint))
    (is-some (map-get? verification-tiers tier)))