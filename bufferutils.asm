%define write_sc 1
%define BUFFER_SIZE 4096

section .text


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
        
        ; flushing
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
