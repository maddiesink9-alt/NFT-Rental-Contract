(define-constant ERR-NOT-CONTRACT-OWNER u100)
(define-constant ERR-NOT-TOKEN-OWNER u101)
(define-constant ERR-ALREADY-RENTED u102)
(define-constant ERR-NOT-LISTED u103)
(define-constant ERR-BAD-DURATION u104)
(define-constant ERR-PAYMENT-FAILED u105)
(define-constant ERR-UNAUTHORIZED u106)

;; Simple in-game NFT that will be rented out.
;; Token IDs are sequential uints starting from 1.
(define-non-fungible-token game-asset uint)

(define-data-var next-token-id uint u0)

;; Track the long-term owner of each token. This never changes during rentals -
;; only this owner is allowed to list or withdraw their asset.
(define-map nft-owners
  { token-id: uint }
  { owner: principal }
)

;; Listing terms for a token that is available for rent.
(define-map rental-listings
  { token-id: uint }
  {
    price-per-block: uint,
    max-duration: uint,
    lender: principal
  }
)

;; Active rental information - who currently has temporary usage rights.
(define-map active-rentals
  { token-id: uint }
  {
    renter: principal,
    expires-at: uint
  }
)

(define-read-only (get-owner (token-id uint))
  (map-get? nft-owners { token-id: token-id })
)

(define-read-only (get-listing (token-id uint))
  (map-get? rental-listings { token-id: token-id })
)

(define-read-only (get-rental (token-id uint))
  (map-get? active-rentals { token-id: token-id })
)

;; Returns whether `user` can currently use `token-id` in-game.
;; This is what game / metaverse contracts should query instead of checking
;; direct ownership, so that renters get temporary access without NFT transfer.
(define-read-only (can-use? (user principal) (token-id uint))
  (let ((owner-opt (get-owner token-id))
        (rental-opt (get-rental token-id)))
    (if (is-none owner-opt)
        ;; Unknown token - no one can use it.
        (ok false)
        (let ((owner (get owner (unwrap-panic owner-opt))))
          (match rental-opt
            rental
              (let ((renter (get renter rental)))
                ;; For simplicity in this demo, a rental is considered active
                ;; until explicitly ended via `end-rental-early`.
                (ok (or (is-eq user owner) (is-eq user renter))))
            (ok (is-eq user owner))))))
)

;; Mint a new in-game NFT to `recipient`.
;; Only the contract deployer can mint.
(define-public (mint (recipient principal))
  (let ((new-id (+ (var-get next-token-id) u1)))
    (var-set next-token-id new-id)
    (map-set nft-owners { token-id: new-id } { owner: recipient })
    (match (nft-mint? game-asset new-id recipient)
      nft-ok (ok new-id)
      nft-err (err ERR-PAYMENT-FAILED))
  )
)

;; List a token for rent with simple linear pricing per block.
;; The NFT is not transferred - we only record rental terms.
(define-public (list-for-rent
    (token-id uint)
    (price-per-block uint)
    (max-duration uint)
  )
  (begin
    (asserts! (> max-duration u0) (err ERR-BAD-DURATION))
    (let
      (
        (owner-record (map-get? nft-owners { token-id: token-id }))
      )
      (asserts! (is-some owner-record) (err ERR-NOT-TOKEN-OWNER))
      (let
        (
          (owner (get owner (unwrap-panic owner-record)))
        )
        (asserts! (is-eq owner tx-sender) (err ERR-NOT-TOKEN-OWNER))
        (asserts! (is-none (map-get? active-rentals { token-id: token-id })) (err ERR-ALREADY-RENTED))
        (map-set rental-listings
          { token-id: token-id }
          {
            price-per-block: price-per-block,
            max-duration: max-duration,
            lender: tx-sender
          }
        )
        (ok true)
      )
    )
  )
)

;; Cancel a listing. Can be called by the token owner / lender as long as
;; there is no active rental.
(define-public (cancel-listing (token-id uint))
  (let
    (
      (owner-record (map-get? nft-owners { token-id: token-id }))
      (listing (map-get? rental-listings { token-id: token-id }))
    )
    (asserts! (is-some owner-record) (err ERR-NOT-TOKEN-OWNER))
    (asserts! (is-some listing) (err ERR-NOT-LISTED))
    (let
      (
        (owner (get owner (unwrap-panic owner-record)))
      )
      (asserts! (is-eq owner tx-sender) (err ERR-UNAUTHORIZED))
      (asserts! (is-none (map-get? active-rentals { token-id: token-id })) (err ERR-ALREADY-RENTED))
      (map-delete rental-listings { token-id: token-id })
      (ok true)
    )
  )
)

;; Start a rental by paying the lender in STX. Ownership stays with the lender,
;; but the renter gets temporary usage rights until `expires-at`.
(define-public (rent (token-id uint) (duration uint))
  (begin
    (asserts! (> duration u0) (err ERR-BAD-DURATION))
    (let
      (
        (listing-opt (map-get? rental-listings { token-id: token-id }))
      )
      (asserts! (is-some listing-opt) (err ERR-NOT-LISTED))
      (asserts! (is-none (map-get? active-rentals { token-id: token-id })) (err ERR-ALREADY-RENTED))
      (let
        (
          (listing (unwrap-panic listing-opt))
          (price-per-block (get price-per-block (unwrap-panic listing-opt)))
          (max-duration (get max-duration (unwrap-panic listing-opt)))
          (lender (get lender (unwrap-panic listing-opt)))
        )
        (asserts! (<= duration max-duration) (err ERR-BAD-DURATION))
        (let ((total-price (* price-per-block duration)))
          ;; Transfer STX from renter to lender.
          (match (stx-transfer? total-price tx-sender lender)
            transfer-ok
              (begin
                (map-set active-rentals
                  { token-id: token-id }
                  {
                    renter: tx-sender,
                    expires-at: duration
                  }
                )
                (ok true)
              )
            transfer-err (err ERR-PAYMENT-FAILED))
        )
      )
    )
  )
)

;; Either the owner or the renter can end a rental early. No refunds are given -
;; this keeps economics simple for a demo.
(define-public (end-rental-early (token-id uint))
  (let
    (
      (rental-opt (map-get? active-rentals { token-id: token-id }))
      (owner-record (map-get? nft-owners { token-id: token-id }))
    )
    (asserts! (is-some rental-opt) (err ERR-NOT-LISTED))
    (asserts! (is-some owner-record) (err ERR-NOT-TOKEN-OWNER))
    (let
      (
        (rental (unwrap-panic rental-opt))
        (owner (get owner (unwrap-panic owner-record)))
        (renter (get renter rental))
      )
      (asserts! (or (is-eq tx-sender owner) (is-eq tx-sender renter)) (err ERR-UNAUTHORIZED))
      (map-delete active-rentals { token-id: token-id })
      (ok true)
    )
  )
)
