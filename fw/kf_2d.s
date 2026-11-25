; kf_2d.s -- one iteration of a 2-state, 1-measurement, 1-input Kalman filter
;
;   x- = Phi x + G u                 P- = Phi P Phi^T + Q
;   K  = P- H^T / (H P- H^T + R)
;   x+ = x- + K (y - H x-)           P+ = (I - K H) P-
;
; Host protocol: while READY=1 write the parameters once, then for every
; sample write y and pulse START; READY returns after 188 cycles and the new
; x and P can be read back.  y is consumed (used as scratch) by the program.
;
; Ported from the original course microcode (legacy-tsmc65 branch,
; src/kf_2d.mem PC 21..159).  Two operand-encoding bugs in the P+ update were
; fixed (marked FIX below): the original subtracted q21 and phi21 instead of
; the saved K2*h2*p21 / K2*h2*p22 terms.  They were invisible in the original
; test because h2 = q21 = phi21 = 0 there.

; ---- data bank map --------------------------------------------------------
.reg x1     0       ; state estimate
.reg x2     1
.reg p11    2       ; error covariance P
.reg p12    3
.reg p21    4
.reg p22    5
.reg phi11  6       ; state transition Phi
.reg phi12  7
.reg phi21  8
.reg phi22  9
.reg q11   10       ; process noise covariance Q
.reg q12   11
.reg q21   12
.reg q22   13
.reg h1    14       ; measurement row H
.reg h2    15
.reg r11   16       ; measurement noise variance R
.reg g1    17       ; control input column G
.reg g2    18
.reg u     19       ; control input
.reg y     20       ; measurement (input, clobbered)
.reg t21   21       ; scratch
.reg t22   22
.reg t23   23
.reg t24   24
.reg t25   25
.reg t26   26
.reg t27   27
.reg t28   28
.reg t29   29
.reg t30   30
.reg t31   31

; ==== time update: x- = Phi x + G u  (t21 = x1-, t22 = x2-) ================
    mul  sr, phi11, x1
    mov  t21, sr
    mul  sr, phi12, x2
    mov  t22, sr
    add  t21, t21, t22          ; phi11*x1 + phi12*x2
    mul  sr, g1, u
    mov  t22, sr
    add  t21, t21, t22          ; x1-
    mul  sr, phi21, x1
    mov  t22, sr
    mul  sr, phi22, x2
    mov  t23, sr
    add  t22, t22, t23          ; phi21*x1 + phi22*x2
    mul  sr, g2, u
    mov  t23, sr
    add  t22, t22, t23          ; x2-

; ==== time update: P- = (Phi P) Phi^T + Q ==================================
    mul  sr, phi11, p11
    mov  t23, sr
    mul  sr, phi12, p21
    mov  t24, sr
    add  t23, t23, t24          ; (Phi P)11
    mul  sr, phi11, p12
    mov  t24, sr
    mul  sr, phi12, p22
    mov  t25, sr
    add  t24, t24, t25          ; (Phi P)12
    mul  sr, phi21, p11
    mov  t25, sr
    mul  sr, phi22, p21
    mov  t26, sr
    add  t25, t25, t26          ; (Phi P)21
    mul  sr, phi21, p12
    mov  t26, sr
    mul  sr, phi22, p22
    mov  t27, sr
    add  t26, t26, t27          ; (Phi P)22

    mul  sr, t23, phi11
    mov  t27, sr
    mul  sr, t24, phi12
    mov  t28, sr
    add  t27, t27, t28
    add  sr, t27, q11
    mov  p11, sr                ; P-11
    mul  sr, t23, phi21
    mov  t27, sr
    mul  sr, t24, phi22
    mov  t28, sr
    add  t27, t27, t28
    add  sr, t27, q12
    mov  p12, sr                ; P-12
    mul  sr, t25, phi11
    mov  t27, sr
    mul  sr, t26, phi12
    mov  t28, sr
    add  t27, t27, t28
    add  sr, t27, q21
    mov  p21, sr                ; P-21
    mul  sr, t25, phi21
    mov  t27, sr
    mul  sr, t26, phi22
    mov  t28, sr
    add  t27, t27, t28
    add  sr, t27, q22
    mov  p22, sr                ; P-22

; ==== gain: K = P- H^T / S,  S = H P- H^T + R ==============================
    mul  sr, p11, h1
    mov  t27, sr
    mul  sr, p12, h2
    mov  t28, sr
    add  t27, t27, t28          ; (P- H^T)1
    mul  sr, p21, h1
    mov  t28, sr
    mul  sr, p22, h2
    mov  t29, sr
    add  t28, t28, t29          ; (P- H^T)2
    mul  sr, h1, t27
    mov  t29, sr
    mul  sr, h2, t28
    mov  t30, sr
    add  t29, t29, t30          ; H P- H^T
    add  t29, t29, r11          ; S
    div  sr, t27, t29
    mov  t23, sr                ; K1
    div  sr, t28, t29
    mov  t24, sr                ; K2

; ==== state update: x+ = x- + K (y - H x-) =================================
    mul  sr, h1, t21
    mov  t25, sr
    mul  sr, h2, t22
    mov  t26, sr
    add  t25, t25, t26          ; H x-
    sub  sr, y, t25
    mov  t25, sr                ; innovation
    mul  sr, t23, t25
    mov  t26, sr
    add  sr, t21, t26
    mov  x1, sr                 ; x1+
    mul  sr, t24, t25
    mov  t26, sr
    add  sr, t22, t26
    mov  x2, sr                 ; x2+

; ==== covariance update: P+ = (I - K H) P- =================================
    mul  sr, t23, h1
    mov  t25, sr                ; K1 h1
    mul  sr, t23, h2
    mov  t26, sr                ; K1 h2
    mul  sr, t24, h1
    mov  t27, sr                ; K2 h1
    mul  sr, t24, h2
    mov  t28, sr                ; K2 h2
    ; save the K2 terms before p11/p12 are overwritten
    mul  sr, t27, p11
    mov  t21, sr                ; K2 h1 p11
    mul  sr, t28, p21
    mov  t22, sr                ; K2 h2 p21
    mul  sr, t27, p12
    mov  t31, sr                ; K2 h1 p12
    mul  sr, t28, p22
    mov  y, sr                  ; K2 h2 p22 (y is no longer needed)
    ; P+11 = p11 - K1 h1 p11 - K1 h2 p21
    mul  sr, t25, p11
    mov  t29, sr
    mul  sr, t26, p21
    mov  t30, sr
    sub  sr, p11, t29
    mov  t29, sr
    sub  sr, t29, t30
    mov  p11, sr                ; P+11
    ; P+12 = p12 - K1 h1 p12 - K1 h2 p22
    mul  sr, t25, p12
    mov  t29, sr
    mul  sr, t26, p22
    mov  t30, sr
    sub  sr, p12, t29
    mov  t29, sr
    sub  sr, t29, t30
    mov  p12, sr                ; P+12
    ; P+21 = p21 - K2 h1 p11 - K2 h2 p21
    sub  sr, p21, t21
    mov  t29, sr
    sub  sr, t29, t22           ; FIX: original subtracted q21 here
    mov  p21, sr                ; P+21
    ; P+22 = p22 - K2 h1 p12 - K2 h2 p22
    sub  sr, p22, t31
    mov  t29, sr
    sub  sr, t29, y             ; FIX: original subtracted phi21 here
    mov  p22, sr                ; P+22

    halt
