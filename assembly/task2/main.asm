section .data
    string_msg db "Original string: ", 0
    string_msg_len equ $ - string_msg
    reversed_string_msg db "Reversed string: ", 0
    reversed_string_msg_len equ $ - reversed_string_msg
    string db 'Hello, World!', 0
    string_len equ $-string
    reversed_string db string_len dup(0)
    newline db 10

section .text
    global _start

_start:
    ; Print original string
    push string_msg_len
    push string_msg
    call print_string
    add esp, 8

    push string_len
    push string
    call print_string
    add esp, 8

    push 1
    push newline
    call print_string
    add esp, 8

    ; Reverse the string
    mov ecx, string_len
    dec ecx                     ; Exclude the null terminator

    push ecx
    push reversed_string
    push string
    call reverse_string
    add esp, 12

    ; Print reversed string
    push reversed_string_msg_len
    push reversed_string_msg
    call print_string
    add esp, 8

    push string_len
    push reversed_string
    call print_string
    add esp, 8

    push 1
    push newline
    call print_string
    add esp, 8

    ; Exit the program
    mov eax, 1                  ; Syscall number for exit
    xor ebx, ebx                ; Exit code 0
    int 0x80                    ; Call kernel to exit

reverse_string:
    ; Parameters:
    ; [ebp+8] - address of the source string
    ; [ebp+12] - address of the destination string
    ; [ebp+16] - length of the string

    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edi
    push esi

    ; Initialize pointers
    mov ecx, [ebp+16]           ; Length of the string
    mov esi, [ebp+8]            ; Source: Start of the original string
    mov edi, [ebp+12]           ; Destination: Start of the reversed string
    add edi, ecx                ; Move edi to the end of the destination string
    dec edi                     ; Point to the last character position

.reverse_loop:
    mov al, [esi]               ; Load byte from original string
    cmp al, 0                   ; Check if end of string (null terminator)
    je .done                    ; If yes, exit

    ; Convert to uppercase if it is a lowercase letter
    cmp al, 'a'                 ; Check if character is lowercase
    jb .no_conversion           ; If below 'a', no conversion needed
    cmp al, 'z'                 ; Check if character is above 'z'
    ja .no_conversion           ; If above 'z', no conversion needed
    sub al, 0x20                ; Convert to uppercase

.no_conversion:
    mov [edi], al               ; Store the character in the reversed string
    inc esi                     ; Move to the next character in the original string
    dec edi                     ; Move to the previous position in the reversed string
    jmp .reverse_loop           ; Repeat the loop

.done:
    mov byte [edi+ecx+1], 0     ; Store null terminator at the end of the reversed string

    pop esi
    pop edi
    pop ecx
    pop eax
    pop ebp
    ret

print_string:
    ; Parameters:
    ; [ebp+8] - address of the string
    ; [ebp+12] - length of the string

    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx

    mov eax, 4               ; syscall number for sys_write
    mov ebx, 1               ; file descriptor for stdout
    mov ecx, [ebp+8]         ; address of the string
    mov edx, [ebp+12]        ; length of the string
    int 0x80                 ; call kernel

    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret
