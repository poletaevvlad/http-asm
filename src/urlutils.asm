section .text

; input: al - hex digit
; output: al - numeric value or 10h on error
; mutates: al
; breaks calling convention
_hex_to_digit:
    cmp al, '0'
    jb .error
    cmp al, '9'
    ja .not_number
    sub al, '0'
    ret
    
    .not_number:
    cmp al, 'A'
    jb .error
    cmp al, 'F'
    ja .not_uppercase
    sub al, 'A'
    add al, 10
    ret
    
    .not_uppercase:
    cmp al, 'a'
    jb .error
    cmp al, 'f'
    ja .error
    sub al, 'a'
    add al, 10
    ret

    .error:
    mov al, 10h
    ret

; input: rdi - pointer to the first char of hex number
; output: al - value
;         ah - 1 on success, 0 otherwise
;         rdi - pointer to the second char of hex number
; mutates: rax, rdi
_parse_codepoint:
    mov al, [rdi]
    call _hex_to_digit
    cmp al, 10h
    jz .error
    mov ah, al
    
    inc rdi
    mov al, [rdi]
    call _hex_to_digit
    cmp al, 10h
    jz .error
    
    xchg al, ah
    shl al, 4
    or al, ah
    mov ah, 1
    ret

    .error:
    xor ah, ah
    ret


; input: rdi - pointer to url string
; output: rax - 1 if valid url, 0 otherwise
; mutates: rdi, rax
_url_decode:
    push rsi
    mov rsi, rdi
    
    .loop:
        mov al, [rdi]
        test al, al
        jz .done
        
        cmp al, '+'
        jne .skip_plus
        ; plus
           mov al, ' '
           jmp .loop_end
        .skip_plus:
        
        cmp al, '%'
        jne .skip_percent
        ; percent
            inc rdi
            call _parse_codepoint
            test ah, ah
            jz .error
        .skip_percent:
        
        .loop_end:
        mov [rsi], al
        
        inc rdi
        inc rsi
    jmp .loop
    .done:
    mov [rsi], BYTE 0
    mov rax, 1
    jmp .end
    .error:
    mov rax, 0
    .end:
    pop rsi
    ret
    
; input: rdi - zero-terminated url
; output: rax - contains 0 if URL is invalid, non-zero otherwise
; mutates: rdi
_check_dot_segments:
    push rcx
    mov cl, [rdi]
    test cl, cl
    jz .end
    cmp cl, '/'
    jne .loop_over_segments
    inc rdi

    .loop_over_segments:
        xor rax, rax
        .counting_dots:
           mov cl, [rdi]
           cmp cl, '.'
           jne .dots_end
           inc rdi
           inc rax
        jmp .counting_dots
        
        .dots_end:
            test cl, cl
            jz .segment_end
            cmp cl, '/'
            je .segment_end
            xor rax, rax
            inc rdi
            mov cl, [rdi]
        jmp .dots_end
        
        .segment_end:
        cmp rax, 2
        je .fail
        test cl, cl
        jz .end
        inc rdi
    jmp .loop_over_segments
        
    .fail:
    mov rax, 0
    jmp .post
    .end:
    mov rax, 1    
    .post:
    pop rcx
    ret
