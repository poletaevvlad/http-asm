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

section .bss
    path resq 1
    pathLength resq 1

section .data
    respFile            db      "HTTP/1.0 200 OK", 13, 10, "Connection: Closed", 13, 10, 13, 10
    respFileLength      equ     $ - respFile
    
    dirTemplatePrefix   incbin  "res/dir-template-prefix"
                        db      0
    dirTemplatePostfix  incbin  "res/dir-template-postfix"
    dirTemplatePostfixLength equ $ - dirTemplatePostfix
    dirTemplateEntry    db      '    <a href="/%%">%</a><br>', 13, 10, 0

    error400            db      "400 Bad Request", 0
    error403            db      "403 Forbidden", 0
    error404            db      "404 Not Found", 0
    error405            db      "405 Method Not Allowed", 0
    
    errorTemplate       incbin  "res/error-template"
                        db      0

    rootDirectory       db      "[root]", 0

section .text


; input: rdi - pointer to error description
;        rsi - file descriptor
_send_error:
    push rbp
    mov rbp, rsp
    push rdi
    push rdi
    push rdi
    
    mov rdi, errorTemplate
    mov rdx, rsi
    lea rsi, [rbp - 24]
    call _write_template
    
    add rsp, 24
    pop rbp
    ret


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
;        r8  - parent path
; output: rax - new buffer end point
; mutates: r8, rsi
_push_dir_entry:
    push rcx
    push rcx
    push r8
    mov rcx, dirTemplateEntry
    mov r8, rsp
    call _buffer_push_template_values
    add rsp, 16
    pop rcx
    ret


; input: rdi - pointer to file path
; output: rax - poitner to the file name
;         r13 - end of directory name
_get_file_name:
    push rcx
    mov cl, [rdi]
    test cl, cl
    jz .root
    
    .loop_to_end:
        mov cl, [rdi]
        test cl, cl
        jz .end_found
        inc rdi
    jmp .loop_to_end
    .end_found:
    dec rdi
    mov [rdi], WORD 0
    mov r13, rdi
    dec rdi
    .loop_name:
        dec rdi
        mov cl, [rdi]
        cmp cl, '/'
    jne .loop_name
    inc rdi
    mov rax, rdi
    jmp .end

    .root:
    mov rax, rootDirectory
    lea r13, [rdi - 1]
    .end:
    pop rcx
    ret


; input: rdi - destination file descriptor
;        rsi - source file descriptor
;        rdx - file path
; output: none
_send_directory_contents:
    push rbp
    mov rbp, rsp
    sub rsp, 4096 + BUFFER_SIZE
    mov rbx, rdi
    mov rdi, rdx
    mov rax, [pathLength]
    add rdx, rax
    mov r14, rdx
    mov rdi, rdx
    call _get_file_name
    push rax
    push rax
               
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
    mov rcx, dirTemplatePrefix
    mov r8, rsp
    call _buffer_push_template_values
    mov r9, rax
    mov [r13], WORD '/'
    add rsp, 16


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
        lea rcx, [rsi + 18]
        mov rsi, r9
        mov r8, r14
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
    mov rcx, dirTemplatePostfix
    mov r8, dirTemplatePostfixLength
    call _buffer_push
    
    mov rsi, rax
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
    mov r9, rdi
    
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
    mov rdx, r9

    xor rbx, rbx
    .dir_end_loop:
        mov cl, [rdx + rbx]
        test cl, cl
        jz .dir_end_found
        inc rbx
    jmp .dir_end_loop
    .dir_end_found:
    mov cl, [rdx + rbx - 1]
    cmp cl, '/'
    je .skip_add_slash
    mov BYTE [rdx + rbx], '/'
    mov BYTE [rdx + rbx + 1], 0
    .skip_add_slash:
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
    mov rdi, error403
    mov rsi, rbx
    call _send_error
    jmp .end
    
    .error_no_file:
    mov rdi, error404
    mov rsi, rbx
    call _send_error
    
    .end:
    pop rdi
    test rdi, rdi
    jz .skip_close
    mov rax, close_sc
    syscall
    
    .skip_close:
    ret
