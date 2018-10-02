%include "bufferutils.asm"

%define open_sc 2
%define fstat_sc 5
%define getdents_sc 78
%define write_sc 1
%define close_sc 3

%define S_IFDIR 0040000o
%define S_IFREG 0100000o
%define S_IFMT  0170000o
%define EACCESS 13
%define ENOENT 2

section .data
    respFile            db      "HTTP/1.0 200 OK", 13, 10, "Content-Type: text/plain", 13, 10, "Connection: Closed", 13, 10, 13, 10
    respFileLength      equ     $ - respFile
    
    respDirPref         db      "HTTP/1.0 200 OK", 13, 10, "Content-Type: text/plain", 13, 10, "Connection: Closed", 13, 10, 13, 10, "<html>"
    respDirPrefLength   equ     $ - respDirPref
    respDirItem         db      "<a href=''></a>"
    respDirItemParts    dq      9, 2, 4, 0
    respDirPostf        db      "</html>"
    respDirPostfLength  equ     $ - respDirPostf

    respError403        db      "HTTP/1.0 403 Forbidden", 13, 10, "Content-Type: text/plain", 13, 10, "Connection: Closed", 13, 10, 13, 10, "403. Forbidden"
    respError403Length  equ     $ - respError403
    respError404        db      "HTTP/1.0 404 Not Found", 13, 10, "Content-Type: text/plain", 13, 10, "Connection: Closed", 13, 10, 13, 10, "404. Not Found"
    respError404Length  equ     $ - respError404


section .text

; input: rdi - file descripor
; output: rax - mode_t of a file
; mutates: rsi
_get_file_type:
    push rbp
    mov rbp, rsp    
    mov rax, fstat_sc
    lea rsi, [rbp - 144]
    syscall
    mov eax, [rbp - 120]
    cdqe
    pop rbp
    ret


; input: rdi - destination file descriptor
;        rsi - source file descriptor
; output: none
; mutates: rdx, rsi
_send_file_contents:
    push rbp
    push rbx
    mov rbp, rsp
    sub rsp, 1024
    mov rbx, rsi

    mov eax, write_sc
    mov rsi, respFile
    mov rdx, respFileLength
    syscall

    lea rsi, [rbp - 1024]
    .loop:
        xchg rdi, rbx
        xor rax, rax ; read_sc
        mov rdx, 1024
        syscall
        
        test rax, rax
        jz .end
        
        xchg rbx, rdi
        mov rdx, rax
        mov rax, write_sc
        syscall
    jmp .loop
    
    .end:
    mov rsp, rbp
    pop rbx
    pop rbp
    ret


; input: rdi - buffer start pointer
;        rsi - buffer end pointer
;        rdx - file descriptor that the buffer will be flushed into
;        rcx - data to be pushed into the buffer
;        r8  - length of the data
; output: rax - new buffer end point
; mutates: r8, rcx, rsi
_push_dir_entry:
    push r10
    push r9
    push rbx
    mov rax, respDirItemParts
    mov rbx, rcx
    mov rbx, rcx
    mov r9, r8
    mov r10, respDirItem
    .loop:
        mov rcx, r10
        push rax
        mov r8, [rax]
        call _buffer_push
        mov rsi, rax
        pop rax
        
        mov r8, [rax]
        add r10, r8
        add rax, 8
        mov r8, [rax]
        test r8, r8
        jz .end

        push rax
        mov r8, r9
        mov rcx, rbx
        call _buffer_push
        mov rsi, rax
        pop rax
    jmp .loop
    
    .end:
    mov rax, rsi
    pop rbx
    pop r9
    pop r10
    ret


; input: rdi - destination file descriptor
;        rsi - source file descriptor
; output: none
_send_directory_contents:
    push rbp
    mov rbp, rsp
    sub rsp, 4096 + BUFFER_SIZE
    mov rbx, rdi
           
    mov rax, getdents_sc
    mov rdi, rsi
    lea rsi, [rbp - 4096]
    mov rdx, 4096
    syscall
    lea r10, [rbp - 4096]
    add r10, rax

    lea rdi, [rbp - 4096 - BUFFER_SIZE]
    mov rsi, rdi
    mov rdx, rbx
    lea rcx, [respDirPref]
    mov r8, respDirPrefLength
    call _buffer_push
    mov r9, rax

    lea rsi, [rbp - 4096]            
    .loop:
        mov cl, [rsi + 18]
        cmp cl, '.'
        je .skip_print
        
        xor rcx, rcx
        mov cx, [rsi + 16]
        sub cx, 20
                
        push rsi
        lea rdi, [rbp - 4096 - BUFFER_SIZE]
        mov rdx, rbx
        mov r8, rcx
        lea rcx, [rsi + 18]
        mov rsi, r9
        call _push_dir_entry
        mov r9, rax
        pop rsi    
            
        .skip_print:
        xor rax, rax
        mov ax, [rsi + 16]
        add rsi, rax
        
        cmp rsi, r10
    jb .loop

    lea rdi, [rbp - 4096 - BUFFER_SIZE]
    mov rsi, r9
    mov rdx, rbx
    lea rcx, [respDirPostf]
    mov r8, respDirPostfLength
    call _buffer_push

    lea rdi, [rbp - 4096 - BUFFER_SIZE]
    mov rsi, rax
    mov rdx, rbx
    call _buffer_flush
    
    mov rsp, rbp
    pop rbp
    ret


; input: rdi - address of zero-terminated file name
;        rsi - socket descriptor
; output: none
_serve_file:
    mov rbx, rsi
    mov rax, open_sc
    xor rsi, rsi
    syscall
    cmp eax, 0
    jl .error
    
    push rax
    mov rdi, rax
    call _get_file_type
    and rax, S_IFMT
    test eax, S_IFDIR
    jnz .directory
    test eax, S_IFREG
    jnz .regular_file
    
    ; Unsupported file type
    jmp .error_no_access
    
    .regular_file:
    mov rsi, rdi
    mov rdi, rbx
    call _send_file_contents
    jmp .end
    
    .directory:
    mov rsi, rdi
    mov rdi, rbx
    call _send_directory_contents
    jmp .end
    
    .error:
    push 0
    neg eax
    cmp eax, EACCESS
    je .error_no_access
    cmp eax, ENOENT
    je .error_no_file
    
    ; `open` system call has failed for unexpected reason
    ; defaulting to "403 Forbidden"
    
    .error_no_access:
    mov rdi, rbx
    mov rax, write_sc
    mov rsi, respError403
    mov rdx, respError403Length
    syscall
    jmp .end
    
    .error_no_file:
    mov rdi, rbx
    mov rax, write_sc
    mov rsi, respError404
    mov rdx, respError404Length  
    syscall
    
    .end:
    pop rdi
    test rdi, rdi
    jz .skip_close
    mov rax, close_sc
    syscall
    
    .skip_close:
    ret
