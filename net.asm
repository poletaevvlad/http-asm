%define socket_sc 41
%define bind_sc 49
%define listen_sc 50
%define accept_sc 43
%define shutdown_sc 48

%define AF_INET 2
%define SOCK_STREAM 1

_memzero: ; (rdi: memory, rsi: size)
    push rcx
    mov rcx, rsi
    .loop:
        mov [rdi + rcx - 1], BYTE 0
    loop .loop
    pop rcx
    ret
    
_init_server1: ; (rdi: port)
    push rbp
    mov rbp, rsp
    push rdi
    
    mov rax, socket_sc
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall
    cmp rax, -1
    je .error    
    mov rbx, rax

    pop rax ; port
    xchg ah, al
    sub rsp, 16
    lea rdi, [rbp - 16]
    mov rsi, 16
    call _memzero
    mov [rbp - 16], WORD AF_INET
    mov [rbp - 14], ax
    
    mov rax, bind_sc
    mov rdi, rbx ; socket
    lea rsi, [rbp - 16]
    mov rdx, 16 ; sizeof(sockaddr_in)
    syscall
    mov rsp, rbp
    cmp rax, -1
    je .error

    mov rax, 50 ; listen
    xor rdi, rdi
    mov rdi, rbx ; socket
    mov rsi, 64
    syscall
    cmp rax, -1
    je .error
    
    mov rax, rbx
    jmp .end
    .error:
    mov rax, -1
    .end:
    pop rbp
    ret
