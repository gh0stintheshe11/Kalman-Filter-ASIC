; kf_2d.s -- one iteration of a 2-state, 1-measurement, 1-input Kalman filter
;
;   x- = Phi x + G u                  P- = Phi P Phi^T + Q
;   K  = P- H^T / S,  S = H P- H^T + R
;   x+ = x- + K (y - H x-)            P+ = P- - K (P- H^T)^T
;
; P and Q are covariance matrices, hence symmetric: only p11, p12, p22 and
; q11, q12, q22 are used (p21 and q21 are ignored), and (I - K H) P- is
; evaluated as P- - K (P- H^T)^T, reusing P- H^T from the gain.  Every
; instruction is a dot product of up to two terms plus an addend, so each
; matrix element is one instruction.  The products are exactly those of the
; original course design (the sums are exact), so on its test case the
; results are identical bit for bit.
;
; Scheduling: an instruction should not read a register as a factor that
; the instruction just before it writes (the pipeline would stall for a
; cycle; results are forwarded from WB, so the one before that is fine, and
; so is an addend).  The reciprocal unit is started by S and delivers 1/S
; to the instruction issued six cycles later; x- and the innovation fill
; the gap.  22 instructions, 24 cycles (one stall).
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

; ==== A = Phi P ==============================================================
    a11  = phi11*p11 + phi12*p12
    a12  = phi11*p12 + phi12*p22
    a21  = phi21*p11 + phi22*p12
    a22  = phi21*p12 + phi22*p22

; ==== P- = A Phi^T + Q (overwrites P) ========================================
    p11  = q11 + a11*phi11 + a12*phi12
    p12  = q12 + a11*phi21 + a12*phi22
    p22  = q22 + a21*phi21 + a22*phi22

; ==== P- H^T, S = H P- H^T + R, RINV <- 1/S ==================================
    pht1 = p11*h1 + p12*h2
    pht2 = p12*h1 + p22*h2
    x1m  = g1*u                     ; x- (below) while S waits for pht2
    s    = r11 + h1*pht1 + h2*pht2, rcp

; ==== x- = Phi x + G u, innovation (while 1/S is computed) ===================
    x1m  = x1m + phi11*x1 + phi12*x2
    x2m  = g2*u
    x2m  = x2m + phi21*x1 + phi22*x2
    inn  = y - h1*x1m - h2*x2m

; ==== K = P- H^T / S =========================================================
    k1   = pht1*rinv
    k2   = pht2*rinv

; ==== x+ = x- + K inn, P+ = P- - K (P- H^T)^T ================================
    p11  = p11 - k1*pht1
    p12  = p12 - k1*pht2
    p22  = p22 - k2*pht2
    x1   = x1m + k1*inn
    x2   = x2m + k2*inn

    halt
