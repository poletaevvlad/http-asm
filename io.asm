%define write_sc 1

section .text

_strlen: ; (rdi: string)
    push rcx
    xor rax, rax
    .loop:
        mov cl, [rdi + rax]
        test cl, cl
        jz .end
        add rax, 1
        jmp .loop
    .end:
    pop rcx
    ret

_out_string: ; (rdi: string)
    call _strlen
    mov rdx, rax
    mov rax, write_sc
    mov rsi, rdi
    mov rdi, 1
    syscall
    ret
    
_atoi: ; (rdi: string)
    push rdx
    push rcx
    xor rax, rax
    xor ch, ch
    .loop:
        mov cl, BYTE [rdi]
        test cl, cl
        jz .end
        mov dx, WORD 10
        mul dx
        sub cl, '0'
        add ax, cx
        add rdi , 1
    jmp .loop
    .end:
    pop rcx
    pop rdx
    ret