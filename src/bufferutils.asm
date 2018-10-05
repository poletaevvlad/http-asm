%define write_sc 1
%define BUFFER_SIZE 8

section .text

__inline_flush:
    push rax
    push rsi
    push rdi
    push rdx
    push rcx
    
    mov rax, write_sc
    mov rsi, rdi
    mov rdi, rdx
    mov rdx, BUFFER_SIZE
    syscall
    
    pop rcx
    pop rdx
    pop rdi
    pop rsi
    pop rax
    ret
    

; input: rdi - buffer start pointer
;        rsi - buffer end pointer
;        rdx - file descriptor that the buffer will be flushed into
;        rcx - data to be pushed into the buffer
;        r8  - length of the data
; output: rax - new buffer end point
; mutates: r8, rcx, rsi
_buffer_push:
    push rbx
    lea rax, [rdi + BUFFER_SIZE] ; end of buffer
    
    .loop:
        mov bl, [rcx]
        mov [rsi], bl
        test bl, bl
        jz .end
        
        inc rsi
        inc rcx
        cmp rsi, rax
        jne .skip_flush
            call __inline_flush
            mov rsi, rdi
        .skip_flush:
        
        dec r8
        test r8, r8
    jnz .loop
    .end:
    mov rax, rsi
    pop rbx
    ret


; input: rdi - buffer start pointer
;        rsi - buffer end pointer
;        rdx - file descriptor that the buffer will be flushed into
;        rcx - null-terminated template
; output: rax - new buffer end point
;         rcx - pointer to '%' or '\0' in template string
; mutates: r8, rcx, rsi
_buffer_push_template:
    push rbx
    lea rax, [rdi + BUFFER_SIZE] ; end of buffer
    
    .loop:
        mov bl, [rcx]
        test bl, bl
        jz .end
        cmp bl, '%'
        je .end
        mov [rsi], bl
        
        inc rsi
        inc rcx
        cmp rsi, rax
        jne .skip_flush
            call __inline_flush
            mov rsi, rdi
        .skip_flush:
    jmp .loop
    .end:
    mov rax, rsi
    pop rbx
    ret


; input: rdi - buffer start pointer
;        rsi - buffer end pointer
;        rdx - file descriptor that the buffer will be flushed into
;        rcx - null-terminated template
;        r8  - array of temlate field values
; output: rax - new buffer end point
; mutates: r8, rcx, rsi
_buffer_push_template_values:
    push rbx
    mov r12, r8
    .loop:
        call _buffer_push_template
        mov rsi, rax
        mov bl, [rcx]
        test bl, bl
        jz .end
        inc rcx

        push rcx
        mov rcx, [r12]
        mov r8, 0xFFFFFFFF
        call _buffer_push
        mov rsi, rax
        add r12, 8
        pop rcx
    jmp .loop

    .end:
    mov rax, rsi
    pop rbx
    ret


; input: rdi - buffer start pointer
;        rsi - buffer end pointer
;        rdx - file descriptor that the buffer will be flushed into
; output: none
; mutates: rsi, rdi, rdx, rax
_buffer_flush:
    sub rsi, rdi
    test rsi, rsi
    jz .end
    mov rax, rsi
    
    mov rsi, rdi
    mov rdi, rdx
    mov rdx, rax
    mov rax, write_sc
    syscall
    .end:
    ret


; input: rdi - pointer to zero-terminated template
;        rsi - array of template field values
;        rdx - file descriptor
; output: none
; muttes: r11, rcx, rdi, rbx, r8
_write_template:
    push rbp
    mov rbp, rsp
    sub rsp, BUFFER_SIZE
    
    mov rcx, rdi
    mov r8, rsi
    lea rdi, [rbp - BUFFER_SIZE]
    mov rsi, rdi
    call _buffer_push_template_values

    lea rdi, [rbp - BUFFER_SIZE]
    mov rsi, rax
    call _buffer_flush
    
    mov rsp, rbp
    pop rbp
    ret
