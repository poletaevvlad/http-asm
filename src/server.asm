%include "diskio.asm"
%include "urlutils.asm"

%define socket_sc 41
%define bind_sc 49
%define listen_sc 50
%define accept_sc 43
%define shutdown_sc 48
%define setsockopt_sc 54

%define AF_INET 2
%define SOCK_STREAM 1

%define SOL_SOCKET 1
%define SO_REUSEADDR 2

%define LINE_BUFFER_SIZE 512

section .data
    method_get db "GET", 0


section .text

; input: rdi - port number
; output: rax - socket or -1 on fail
_init_server:
    push rbp
    mov rbp, rsp

    mov rax, rdi
    xchg ah, al
    mov r9, rax

    mov rax, socket_sc
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .error    
    mov rbx, rax
    
    sub rsp, 4
    mov DWORD [rbp - 4], 1
   
    mov rax, setsockopt_sc
    mov rdi, rbx
    mov rsi, SOL_SOCKET
    mov rdx, SO_REUSEADDR
    lea r10, [rbp - 4]
    mov r8, 4
    syscall

    sub rsp, 16
    
    mov rcx, 12
    lea rsi, [rbp - 12]
    .mem_zero:
        mov [rsi], BYTE 0
        inc rsi
    loop .mem_zero
    mov [rbp - 16], WORD AF_INET
    mov [rbp - 14], r9w
    
    mov rax, bind_sc
    mov rdi, rbx
    lea rsi, [rbp - 16]
    mov rdx, 16
    syscall
    mov rsp, rbp
    cmp rax, 0
    jl .error
    
    mov rax, listen_sc
    mov rdi, rbx ; socket
    mov rsi, 64
    syscall
    cmp rax, 0
    jl .error

    mov rax, rbx
    jmp .end
    .error:
    mov rax, -1
    .end:
    pop rbp
    ret



; input: rdi - pointer to http request string
; output: rax - pointer to the start of url or 0 if method is invalid
_parse_request: 
    push rcx
    mov rsi, method_get
    .loop:
        mov cl, [rdi]
        cmp cl, 13
        je .error
        test cl, cl
        jz .error
        
        mov ch, [rsi]
        test ch, ch
        jz .skip_space_loop
        
        cmp ch, cl
        jne .error
        inc rsi
        inc rdi
    jmp .loop
    .skip_space_loop:
        mov cl, [rdi]
        cmp cl, 13
        je .error
        test cl, cl
        jz .error
        cmp cl, ' '
        jne .done
        inc rdi
    jmp .skip_space_loop

    .done:
    cmp cl, '/'
    jne .skip_add
    inc rdi
    .skip_add:
    
    mov rax, rdi
    jmp .end
    .error:
    mov eax, 0
    
    .end:
    pop rcx
    ret
    
    
; input: rdi - file descriptor
;        rsi - buffer
; output: rax - pointer to line end or 0 if no \13 symbol was found
_read_line:
    xor r8, r8

    .read_loop:
        xor rax, rax ; read_sc
        sub rdx, rsi
        mov rdx, LINE_BUFFER_SIZE
        sub rdx, r8
        test rdx, rdx
        jz .not_found
        syscall
        cmp rax, 0
        jng .not_found

        push rdi           
        add r8, rax
        mov rdi, rsi
        add rdi, rax
        
        .check_endl_loop:
            mov cl, [rsi]
            cmp cl, 13
            je .found
            inc rsi
            cmp rdi, rsi
        jne .check_endl_loop
        
        pop rdi
    jmp .read_loop
    
    .found:
    mov rax, rsi
    add rsp, 8
    ret
    
    .not_found:
    mov rax, 0
    ret


; input: rdi - client's descriptor
; output: none
_handle_client:
    push rbp
    mov rbp, rsp
    sub rsp, LINE_BUFFER_SIZE
    mov rcx, rdi
    mov r9, rcx        
    lea rsi, [rbp - LINE_BUFFER_SIZE]
    call _read_line
    test rax, rax
    jz .bad_request
    
    lea rdi, [rbp - LINE_BUFFER_SIZE]
    call _parse_request
    test rax, rax
    jz .unsupported_method   
    push rax
    
    xor rcx, rcx
    .terminate_path_loop:
        mov cl, [rax]
        cmp cl, ' '
        je .terminate_path_loop_end
        cmp cl, 13
        je .terminate_path_loop_end
        cmp cl, '?'
        je .terminate_path_loop_end
        inc rax
    jmp .terminate_path_loop
    .terminate_path_loop_end:
    mov [rax], BYTE 0
    mov rdi, [rsp]
    push rdi
    call _url_decode
    
    mov rdi, [rsp + 8]
    call _check_dot_segments
    test rax, rax
    jz .bad_request
    
    pop rdi
    pop rax
    
            
    mov rsp, rax
    mov rcx, [pathLength]
    sub rsp, rcx
    mov rdi, [path]
    mov rsi, rsp
    .strcopy:
        mov al, [rdi]
        mov [rsi], al
        inc rsi
        inc rdi
    loop .strcopy
    
    mov rsi, r9 ; socket descr.
    mov rdi, rsp
    call _serve_file
    
    jmp .end
    
    .unsupported_method:
    mov rdi, error405
    mov rsi, r9
    call _send_error
    jmp .end
        
    .bad_request:
    mov rdi, error400
    mov rsi, r9
    call _send_error
    
    .end:
    mov rsp, rbp
    pop rbp
    ret


; input: rdi - socket descr.
; output: none
_server_loop:
    mov rax, accept_sc
    xor rsi, rsi
    xor rdx, rdx
    syscall
    push rdi
    push rax
    
    mov rdi, rax
    call _handle_client
    
    mov rax, shutdown_sc
    pop rdi
    mov rsi, 2
    syscall
    pop rdi
    jmp _server_loop
    ret


