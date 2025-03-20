; ========================================================================
;
; (C) Copyright 2023 by Molly Rocket, Inc., All Rights Reserved.
;
; This software is provided 'as-is', without any express or implied
; warranty. In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Please see https://computerenhance.com for further information
;
; ========================================================================

; ========================================================================
; LISTING 52
; ========================================================================

bits 16

mov dx, 6
mov bp, 1000

mov si, 0
; init_loop_start:
mov [bp + si], si
add si, 2
cmp si, dx
;jnz init_loop_start
jnz -9

mov bx, 0
mov si, 0
;add_loop_start:
mov cx, [bp + si]
add bx, cx
add si, 2
cmp si, dx
; jnz add_loop_start
jnz -11
