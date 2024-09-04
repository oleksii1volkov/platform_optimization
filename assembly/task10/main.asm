section .data
    orig_msg db "Original message: ", 0
    orig_msg_len equ $ - orig_msg
    enc_msg db "Encrypted message: ", 0
    enc_msg_len equ $ - enc_msg
    dec_msg db "Decrypted message: ", 0
    dec_msg_len equ $ - dec_msg
    data db "Hello, World!", 0
    data_len equ $-data
    newline db 10

section .bss
    enc_data resb data_len

section .text
    global _start

_start:
    ; Print original message
    mov eax, 4
    mov ebx, 1
    mov ecx, orig_msg
    mov edx, orig_msg_len
    int 0x80

    ; Print original data
    mov eax, 4
    mov ebx, 1
    mov ecx, data
    mov edx, data_len
    int 0x80

    ; Print newline
    mov eax, 4
    mov ebx, 1
    mov ecx, newline
    mov edx, 1
    int 0x80

    ; Encrypt the data
    call encrypt_data

    ; Print encrypted message
    mov eax, 4
    mov ebx, 1
    mov ecx, enc_msg
    mov edx, enc_msg_len
    int 0x80

    ; Print encrypted data
    mov eax, 4
    mov ebx, 1
    mov ecx, enc_data
    mov edx, data_len
    int 0x80

    ; Print newline
    mov eax, 4
    mov ebx, 1
    mov ecx, newline
    mov edx, 1
    int 0x80

    ; Transfer the encrypted data (no need for segment overrides)
    call transfer_data

    ; Decrypt the data
    call decrypt_data

    ; Print decrypted message
    mov eax, 4
    mov ebx, 1
    mov ecx, dec_msg
    mov edx, dec_msg_len
    int 0x80

    ; Print decrypted data
    mov eax, 4
    mov ebx, 1
    mov ecx, enc_data
    mov edx, data_len
    int 0x80

    ; Print newline
    mov eax, 4
    mov ebx, 1
    mov ecx, newline
    mov edx, 1
    int 0x80

    ; Exit
    mov eax, 1
    xor ebx, ebx
    int 0x80

encrypt_data:
    mov esi, data
    mov edi, enc_data
    mov ecx, data_len

.encrypt_loop:
    lodsb
    rol al, 1
    stosb
    loop .encrypt_loop
    ret

transfer_data:
    ; In a flat memory model, this is essentially a no-op
    ; Since `enc_msg` is already in memory, there's no need to move it between segments
    ; Just copy the encrypted data if necessary
    mov esi, enc_data
    mov edi, enc_data; Normally, this would be to another segment, but in flat memory, this is not needed
    mov ecx, data_len

.transfer_loop:
    lodsb
    stosb
    loop .transfer_loop
    ret

decrypt_data:
    mov esi, enc_data
    mov edi, enc_data
    mov ecx, data_len

.decrypt_loop:
    lodsb
    ror al, 1
    stosb
    loop .decrypt_loop
    ret
