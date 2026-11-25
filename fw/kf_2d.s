; kf_2d.s -- one iteration of a 2-state, 1-measurement, 1-input Kalman filter
;
;   x- = Phi x + G u                  P- = Phi P Phi^T + Q
;   K  = P- H^T / S,  S = H P- H^T + R
;   x+ = x- + K (y - H x-)            P+ = P- - K (P- H^T)^T
;
; P and Q are covariance matrices, hence symmetric: only p11, p12, p22 and
; q11, q12, q22 are used (p21 and q21 are ignored), and (I - K H) P- is
; evaluated as P- - K (P- H^T)^T, reusing P- H^T from the gain.
;
; Scheduling: an instruction must not read a register written by either of
; the two instructions before it (the pipeline would stall), and RINV is
; valid 8 cycles after RCP issues.  1/S is computed while x- and the
; innovation are evaluated.
;
; Host protocol: while READY=1 write the parameters once, then for every
; sample write y and pulse START; read x1, x2, p11, p12, p22 when READY
; returns.

; ---- data bank map --------------------------------------------------------
.reg x1     0       ; state estimate
.reg x2     1
.reg p11    2       ; error covariance P (symmetric)
.reg p12    3
.reg p21    4       ; unused (= p12)
.reg p22    5
.reg phi11  6       ; state transition Phi
.reg phi12  7
.reg phi21  8
.reg phi22  9
.reg q11   10       ; process noise covariance Q (symmetric)
.reg q12   11
.reg q21   12       ; unused (= q12)
.reg q22   13
.reg h1    14       ; measurement row H
.reg h2    15
.reg r11   16       ; measurement noise variance R
.reg g1    17       ; control input column G
.reg g2    18
.reg u     19       ; control input
.reg y     20       ; measurement
.reg x1m   21       ; scratch
.reg x2m   22
.reg a11   23       ; A = Phi P, later K
.reg a12   24
.reg a21   25
.reg a22   26
.reg pht1  27       ; P- H^T
.reg pht2  28
.reg s     29       ; innovation variance S
.reg inn   30       ; innovation
.reg k1    23
.reg k2    24

; ==== A = Phi P ============================================================
    mul  acc, phi11, p11
    mac  a11, phi12, p12
    mul  acc, phi11, p12
    mac  a12, phi12, p22
    mul  acc, phi21, p11
    mac  a21, phi22, p12
    mul  acc, phi21, p12
    mac  a22, phi22, p22

; ==== P- = A Phi^T + Q (overwrites P) ======================================
    lda  acc, q11
    mac  acc, a11, phi11
    mac  p11, a12, phi12
    lda  acc, q12
    mac  acc, a11, phi21
    mac  p12, a12, phi22
    lda  acc, q22
    mac  acc, a21, phi21
    mac  p22, a22, phi22

; ==== P- H^T and S = H P- H^T + R ==========================================
    mul  acc, p11, h1
    mac  pht1, p12, h2
    mul  acc, p12, h1
    mac  pht2, p22, h2
    lda  acc, r11
    mac  acc, pht1, h1
    mac  s, pht2, h2

; ==== x- = Phi x + G u, innovation; 1/S in the background ==================
    mul  acc, phi11, x1
    mac  acc, phi12, x2
    rcp  s                      ; RINV <- 1/S
    mac  x1m, g1, u
    mul  acc, phi21, x1
    mac  acc, phi22, x2
    mac  x2m, g2, u
    lda  acc, y
    msb  acc, h1, x1m
    msb  inn, h2, x2m

; ==== K = P- H^T / S =======================================================
    mul  k1, pht1, rinv
    mul  k2, pht2, rinv

; ==== x+ = x- + K inn ======================================================
    lda  acc, x1m
    mac  x1, k1, inn
    lda  acc, x2m
    mac  x2, k2, inn

; ==== P+ = P- - K (P- H^T)^T ===============================================
    lda  acc, p11
    msb  p11, k1, pht1
    lda  acc, p12
    msb  p12, k1, pht2
    lda  acc, p22
    msb  p22, k2, pht2

    halt
