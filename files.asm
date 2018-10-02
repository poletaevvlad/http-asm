%include "io.asm"
%include "net.asm"
%include "io64.inc"

%define open_sc 2
%define close_sc 3
%define fstat_sc 5

section .data
    usage: db "Usage: [prog] PORT PATH", 10, 0
    
    response: db "HTTP/1.0 200 OK", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 14", 13, 10, "Connection: Closed", 13, 10, 13, 10, "Hello, world", 13, 10, 0
    response404: db "HTTP/1.0 404 Not Found", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 16", 13, 10, "Connection: Closed", 13, 10, 13, 10, "404. Not found", 13, 10, 0
    response405: db "HTTP/1.0 405 Method Not Allowed", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 24", 13, 10, "Connection: Closed", 13, 10, 13, 10, "405. Method Not Allowed", 13, 10, 0
    responseHeader: db "HTTP/1.0 200 OK", 13, 10, "Content-Type: text/plain", 13, 10, "Connection: Closed", 13, 10, 13, 10, 0
    
    tst: db "8080", 0
    tst_path: db "/home/vlad", 0
    tst_arr: dq 0, 0, 0
    
    get_method db "GET", 0

section .bss
    path: resq 1

global main
section .text
    
; args: (rdi: source, rsi: destination)
_copy_descriptors: 
    push rbx
    push rdx
    mov rbp, rsp
    sub rsp, 1024

    mov rbx, rsi
    lea rsi, [rbp - 1024]       
    
    .loop:
        xor rax, rax ; read_sc
        mov rdx, 1024
        syscall
        test rax, rax
        jz .end
        
        xchg rbx, rdi
        mov rdx, rax
        mov rax, write_sc
        syscall
        
        xchg rbx, rdi
    jmp .loop
    
    .end:
    mov rsp, rbp
    pop rdx 
    pop rbx
    ret
   
_get_st_mode: ; (rdi: file descr.)
    push rbp
    mov rbp, rsp
    sub rsp, 144
    
    mov rax, fstat_sc
    lea rsi, [rbp - 144]
    syscall
    
    mov eax, [rbp - 128]
    
    mov rsp, rbp
    pop rbp
    ret
      
_send_file: ; (rdi: socket, rsi: path)
    push rax
    push rsi
    push rdx
    push rbx
    push rcx
    mov rbx, rdi

    mov rax, open_sc
    mov rdi, rsi
    xor rsi, rsi ; O_RDONLY = 0
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .error404
    push rax

    .read_loop:
    mov rdi, responseHeader
    call _strlen
    mov rdx, rax    
    mov rax, write_sc
    mov rdi, rbx
    mov rsi, responseHeader
    syscall
    
    mov rdi, [rsp]
    mov rsi, rbx
    call _copy_descriptors
    
    pop rdi    
    mov rax, close_sc
    syscall
    
    jmp .end
    .error404:
    mov rdi, response404
    call _strlen
    mov rdx, rax    
    mov rax, write_sc
    mov rdi, rbx
    mov rsi, response404
    syscall
        
    .end:
    pop rcx
    pop rbx
    pop rdx
    pop rsi
    pop rax
    ret
    
    
_handle_client: ; (rdi: socket)
    push rax
    push rbp
    mov rbp, rsp
    
    mov rax, accept_sc
    xor rsi, rsi
    xor rdx, rdx
    syscall
    mov rbx,  rax ; rbx = fd
    
    sub rsp, 512
    xor rcx, rcx
    
    lea rsi, [rbp - 512]
    
    .read_loop:
        xor rax, rax ; read
        mov rdi, rbx   
        mov rdx, rbp
        sub rdx, rsi
        syscall
        
        mov rdi, rsi 
        add rsi, rax
        cmp rsi, rbp
        jnb .end
        
        .check_endl_loop:
            mov cl, [rdi]
            cmp cl, 13
            je .read_ended
            add rdi, 1
            cmp rdi, rsi
        jne .check_endl_loop
    jmp .read_loop

    .read_ended:
    ; checking method name
    lea rsi, [rbp - 512]   
    mov rdi, get_method
    
    .method_name_loop:
        mov cl, [rsi]
        cmp cl, 13
        je .wrong_method
        mov ch, [rdi]
        test ch, ch
        jz .correct_method
        cmp ch, cl
        jne .wrong_method
        inc rsi
        inc rdi
    jmp .method_name_loop
    
    .correct_method:
    mov cl, [rsi]
    cmp cl, 13
    je .wrong_method
    cmp cl, ' '
    jne .path_found
    inc rsi
    jmp .correct_method
    
    .path_found:
    mov rdi, [path]
    call _strlen
    
    lea rdx, [rbp - 512]
    add rdx, rax
    sub rdx, rsi
    sub rsp, rdx

    mov rdi, rsp
    mov rsi, [path]    
    .path_copy_loop:
        mov cl, [rsi]
        test cl, cl
        jz .path_created
        mov [rdi], cl
        inc rdi
        inc rsi
    jmp .path_copy_loop
        
    .path_created:
        mov cl, [rsp + rax]
        cmp cl, ' '
        je .path_measured
        cmp cl, 13
        je .path_measured
        inc rax
    jmp .path_created

    .path_measured:
    mov [rsp + rax], BYTE 0

    mov rdi, rbx
    mov rsi, rsp
    call _send_file
    
    jmp .end
    
    .wrong_method:
    mov rdi, response405
    call _strlen
    mov rdx, rax 
    mov rax, write_sc
    mov rdi, rbx
    mov rsi, response405
    syscall

    .end:
    mov rax, shutdown_sc
    mov rdi, rbx
    mov rsi, 2
    syscall
        
    mov rsp, rbp
    pop rbp
    pop rax
    ret
    
main:
    mov rbp, rsp; for correct debugging
    
    mov rdi, 3
    mov rax, tst
    mov [tst_arr + 8], rax
    mov rax, tst_path
    mov [tst_arr + 16], rax
    mov rsi, tst_arr
    
    cmp rdi, 3
    je .usage_ok
    mov rdi, usage
    call _out_string
    je .error_finish
    
.usage_ok:
    mov rax, [rsi + 16]
    mov [path], rax
    mov rdi, [rsi + 8]
    call _atoi
    mov rdi, rax
    call _init_server1
    cmp rax, -1
    je .error_finish
    
.accept_loop:
    mov rdi, rax
    call _handle_client
    jmp .accept_loop    
    
.error_finish:
    mov rax, 60
    mov rdi, 1
    syscall