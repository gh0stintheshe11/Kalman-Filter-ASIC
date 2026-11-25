; kf_2d.s -- one iteration of a 2-state, 1-measurement, 1-input Kalman filter
;
;   x- = Phi x + G u                  P- = Phi P Phi^T + Q
;   K  = P- H^T / S,  S = H P- H^T + R
;   x+ = x- + K (y - H x-)            P+ = P- - K (P- H^T)^T
;
; P and Q are covariance matrices, hence symmetric: only p11, p12, p22 and
; q11, q12, q22 are used (p21 and q21 are ignored), and (I - K H) P- is
; evaluated as P- - K (P- H^T)^T, reusing P- H^T from the gain.  MAD/MSD add
; a register to a product, so no instruction is needed to preload ACC.
;
; Scheduling: an instruction should not read a register as A or B that the
; instruction just before it writes (the pipeline would stall for a cycle;
; results are forwarded from WB, so the one before that is fine, and so is
; any addend C).  RINV is valid 7 cycles after RCP issues; 1/S is computed
; while x- and the innovation are evaluated.  This order runs without a
; single stall: 36 instructions, 38 cycles.
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

; ==== A = Phi P (A21, A22 first: P- below needs them last) ================
    mul  acc, phi21, p11
    mac  a21, phi22, p12
    mul  acc, phi21, p12
    mac  a22, phi22, p22
    mul  acc, phi11, p11
    mac  a11, phi12, p12
    mul  acc, phi11, p12
    mac  a12, phi12, p22

; ==== P- = A Phi^T + Q (overwrites P), interleaved with P- H^T ===============
    mad  acc, a11, phi11, q11
    mac  p11, a12, phi12
    mad  acc, a11, phi21, q12
    mac  p12, a12, phi22
    mul  acc, p11, h1           ; P- H^T, first row
    mac  pht1, p12, h2
    mad  acc, a21, phi21, q22
    mac  p22, a22, phi22
    mul  acc, p12, h1           ; P- H^T, second row
    mac  pht2, p22, h2

; ==== S = H P- H^T + R ======================================================
    mad  acc, pht1, h1, r11
    mac  s, pht2, h2

; ==== x- = Phi x + G u, innovation; 1/S in the background ==================
    mul  acc, phi11, x1
    rcp  s                      ; RINV <- 1/S
    mac  acc, phi12, x2
    mac  x1m, g1, u
    mul  acc, phi21, x1
    mac  acc, phi22, x2
    mac  x2m, g2, u
    msd  acc, h1, x1m, y
    msb  inn, h2, x2m

; ==== K = P- H^T / S =======================================================
    mul  k2, pht2, rinv
    mul  k1, pht1, rinv

; ==== x+ = x- + K inn, P+ = P- - K (P- H^T)^T ==============================
    mad  x2, k2, inn, x2m
    mad  x1, k1, inn, x1m
    msd  p22, k2, pht2, p22
    msd  p11, k1, pht1, p11
    msd  p12, k1, pht2, p12

    halt
