section .data
    prompt_operation_msg db "Select operation (1 - Encrypt, 2 - Decrypt): ", 0
    prompt_operation_msg_len equ $ - prompt_operation_msg
    prompt_input_path_msg db "Enter input file path: ", 0
    prompt_input_path_msg_len equ $ - prompt_input_path_msg
    prompt_output_path_msg db "Enter output file path: ", 0
    prompt_output_path_msg_len equ $ - prompt_output_path_msg
    prompt_key_msg db "Enter encryption key: ", 0
    prompt_key_msg_len equ $ - prompt_key_msg
    encrypted_msg db "Encrypted successfully!", 10, 0
    encrypted_msg_len equ $ - encrypted_msg
    decrypted_msg db "Decrypted successfully!", 10, 0
    decrypted_msg_len equ $ - decrypted_msg
    error_invalid_operation_msg db "Invalid option selected!", 10, 0
    error_invalid_operation_msg_len equ $ - error_invalid_operation_msg
    error_open_input_msg db "Error: Cannot open input file!", 10, 0
    error_open_input_msg_len equ $ - error_open_input_msg
    error_open_output_msg db "Error: Cannot open or create output file!", 10, 0
    error_open_output_msg_len equ $ - error_open_output_msg
    max_file_path_length equ 256
    max_encryption_key_length equ 256
    max_buffer_length equ 65536
    newline db 10, 0
    statbuf times 96 db 0
    str_fmt db '%s', 0

section .bss
    input_file_path resb max_file_path_length
    output_file_path resb max_file_path_length
    encryption_key resb max_encryption_key_length
    encryption_key_length resd 1
    operation resb 2
    input_fd resd 1
    output_fd resd 1
    input_buffer_addr resd 1
    output_buffer_addr resd 1
    file_size resd 1

section .text
    global main
    extern printf
    extern fflush

main:
    ; Prompt for operation
    call prompt_operation
    cmp eax, 0
    jnz .invalid_option_error
    jmp .prompt_input_path
    
.invalid_option_error:
    ; Display error message for invalid option
    push error_invalid_operation_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Exit the program
    jmp .exit

.prompt_input_path:
    ; Prompt for input file path
    call prompt_input_path

    ; Attempt to open the input file for reading
    mov eax, 5                  ; sys_open
    mov ebx, input_file_path    ; file path
    mov ecx, 0                  ; read-only mode (O_RDONLY)
    int 0x80

    ; Check if the file was opened successfully
    cmp eax, 0
    js .open_input_error         ; If eax < 0, jump to error

    ; Store the input file descriptor
    mov [input_fd], eax
    jmp .prompt_output_path

.open_input_error:
    ; Display error message for input file
    push error_open_input_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Exit the program
    jmp .exit

.prompt_output_path:
    ; Prompt for output file path
    call prompt_output_path

    ; Attempt to open the output file for reading and writing (create if it doesn't exist)
    mov eax, 5                  ; sys_open
    mov ebx, output_file_path   ; file path
    mov ecx, 0x242              ; read-write, create if not exists, truncate (O_RDWR | O_CREAT | O_TRUNC)
    mov edx, 0o644               ; file permissions (rw-r--r--)
    int 0x80

    ; Check if the file was opened/created successfully
    cmp eax, 0
    js .open_output_error        ; If eax < 0, jump to error

    ; Store the output file descriptor
    mov [output_fd], eax
    jmp .prompt_key

.open_output_error:
    ; Display error message for output file
    push error_open_output_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Close the input file
    mov eax, 6              ; sys_close
    mov ebx, [input_fd]     ; input file descriptor
    int 0x80

    ; Exit the program
    jmp .exit

.prompt_key:
    ; Prompt for encryption key
    call prompt_key
    ; Store the encryption key length
    mov [encryption_key_length], eax

.allocate_buffers:
    ; Allocate memory for the input and output buffers
    push dword [input_fd]
    call get_file_size
    add esp, 4
    mov [file_size], eax

    mov ecx, [file_size]
    call allocate_memory
    mov [input_buffer_addr], eax

    call allocate_memory
    mov [output_buffer_addr], eax

.encrypt_or_decrypt:
    ; Check if the operation is '1' (encrypt) or '2' (decrypt)
    mov bl, byte [operation]
    cmp bl, '1'
    je .encrypt_file
    cmp bl, '2'
    je .decrypt_file

.encrypt_file:
    call encrypt_file

    push encrypted_msg
    push str_fmt
    call print_format
    add esp, 8

    jmp .close_files

.decrypt_file:
    call decrypt_file

    push decrypted_msg
    push str_fmt
    call print_format
    add esp, 8

    jmp .close_files

.close_files:
    ; Close the input and output files

    mov eax, 6              ; sys_close
    mov ebx, [input_fd]     ; input file descriptor
    int 0x80

    mov eax, 6              ; sys_close
    mov ebx, [output_fd]    ; output file descriptor
    int 0x80

.free_buffers:
    mov ecx, [input_buffer_addr]
    call free_memory

    mov ecx, [output_buffer_addr]
    call free_memory

.exit:
    ; Exit the program
    mov eax, 1                  ; sys_exit
    xor ebx, ebx                ; status 0
    int 0x80

prompt_operation:
    ; Display prompt for operation
    push prompt_operation_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Read operation input
    push dword 2
    push operation
    call read_string
    add esp, 8

    xor eax, eax                ; Clear eax for the return value

    ; Check if the operation is valid (either '1' or '2')
    mov bl, byte [operation]
    cmp bl, '1'
    je .done
    cmp bl, '2'
    je .done

    mov eax, 1                 ; Set the error code

.done:
    ret

prompt_input_path:
    ; Display prompt for input file path
    push prompt_input_path_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Read input file path
    push max_file_path_length
    push input_file_path
    call read_string
    add esp, 8

    ; Replace newline character with null terminator
    push input_file_path
    call replace_newline
    add esp, 4

    ret

prompt_output_path:
    ; Display prompt for output file path
    push prompt_output_path_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Read output file path
    push max_file_path_length
    push output_file_path
    call read_string
    add esp, 8

    ; Replace newline character with null terminator
    push output_file_path
    call replace_newline
    add esp, 4

    ret

prompt_key:
    ; Display prompt for encryption key
    push prompt_key_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Read the encryption key from the user
    push max_encryption_key_length
    push encryption_key
    call read_string
    add esp, 8

    ; Replace newline character with null terminator
    push encryption_key
    call replace_newline
    add esp, 4

    ret

replace_newline:
    ; Parameters:
    ; [ebp+8] - address of the input file path
    
    push ebp
    mov ebp, esp
    push ebx
    push esi
    
    mov esi, [ebp+8]            ; Load the address of the input file path
    xor ebx, ebx                ; Initialize the loop counter to 0

.replace_loop:
    lodsb                       ; Load byte from [esi] into AL, and increment ESI
    cmp al, 0                   ; Check if we reached the end of the string (null terminator)
    je .done                    ; If null terminator, exit loop
    inc ebx                     ; Increment the loop counter
    cmp al, 10                  ; Check if the byte is a newline character (\n)
    je .found_newline           ; If newline, jump to replace with null terminator
    jmp .replace_loop           ; Otherwise, continue looping

.found_newline:
    dec ebx                     ; Decrement the loop counter
    dec esi                     ; Move ESI back to point to the newline character
    mov byte [esi], 0           ; Replace newline with null terminator (\0)

.done:
    mov eax, ebx
    pop esi
    pop ebx
    pop ebp
    ret

print_format:
    ; Parameters:
    ; [ebp+8] - address of the format string
    ; [ebp+12] - element to print

    push ebp
    mov ebp, esp
    push ecx
    
    push dword [ebp+12]
    push dword [ebp+8]
    call printf
    add esp, 8

    push 0
    call fflush
    add esp, 4

    pop ecx
    pop ebp
    ret

read_string:
    ; Parameters:
    ; [ebp+8] - address of the string
    ; [ebp+12] - maximum length of the string

    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx

    mov eax, 3                  ; sys_read
    mov ebx, 0                  ; file descriptor (stdin)
    mov ecx, [ebp+8]            ; store input in [ebp+8]
    mov edx, [ebp+12]           ; max length to read
    int 0x80

    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

encrypt:
    ; Parameters:
    ; [ebp+8]  - Address of the input buffer
    ; [ebp+12] - Address of the output buffer
    ; [ebp+16] - Number of bytes to process

    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Load parameters into registers
    mov esi, [ebp+8]        ; Load input buffer address into ESI
    mov edi, [ebp+12]       ; Load output buffer address into EDI
    mov ecx, [ebp+16]       ; Load number of bytes to process into ECX

    xor ebx, ebx            ; EBX will hold the index for the key
    mov edx, [encryption_key_length]   ; Load the key length into EDX

.encrypt_loop:
    cmp ecx, 0              ; Check if there are bytes left to process
    je .done                ; If no more bytes, exit loop

    ; XOR the input byte with the corresponding key byte
    mov al, [esi]           ; Load byte from input buffer
    xor al, [encryption_key + ebx] ; XOR with the key byte
    mov [edi], al           ; Store result in output buffer

    ; Increment pointers and loop counters
    inc esi                 ; Move to the next byte in input buffer
    inc edi                 ; Move to the next byte in output buffer
    inc ebx                 ; Move to the next byte in the key
    dec ecx                 ; Decrement byte counter

    cmp ebx, edx            ; Check if we've reached the end of the key
    jne .encrypt_loop       ; If not, continue with the next key byte
    xor ebx, ebx            ; If yes, reset key index to 0
    jmp .encrypt_loop       ; Repeat the loop

.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

decrypt:
    ; Same as encrypt
    call encrypt
    ret

get_file_size:
    ; Parameters:
    ; [ebp+8] - file descriptor

    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi
    
    mov ebx, [ebp+8]                    ; Store the file descriptor

    ; Get file size using lseek
    mov eax, 19                         ; sys_lseek system call number (19)
    xor ecx, ecx                        ; Offset of 0
    mov edx, 2                          ; SEEK_END (to move to the end of the file)
    int 0x80                            ; Call kernel

    ; Now eax contains the file size (the offset from the beginning to the end)
    mov esi, eax                        ; Store the file size in ESI

    ; Move the file pointer back to the beginning
    mov eax, 19                         ; sys_lseek system call number (19)
    xor ecx, ecx                        ; Offset of 0
    xor edx, edx                        ; SEEK_SET (to move to the beginning of the file)
    int 0x80                            ; Call kernel

    mov eax, esi                        ; Return the file size in EAX

    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

allocate_memory:
    ; Parameters:
    ; ecx contains the size of the memory to allocate

    ; Get the current program break
    mov eax, 45               ; sys_brk system call number
    xor ebx, ebx              ; Current program break (EBX=0)
    int 0x80                  ; Call kernel to get current program break
    mov edx, eax              ; Save current program break in edx

    ; Calculate new program break
    add eax, ecx              ; Add the requested size to the current program break

    ; Set the new program break
    mov ebx, eax              ; New program break address
    mov eax, 45               ; sys_brk system call number
    int 0x80                  ; Call kernel to set new program break

    ; Return the starting address of the allocated memory in eax
    mov eax, edx              ; The starting address of the allocated memory

    ret

free_memory:
    ; Parameters:
    ; ecx - address of the memory to free

    ; Get the current program break
    mov eax, 45               ; sys_brk system call number
    xor ebx, ebx              ; Set ebx to 0 to get the current program break
    int 0x80                  ; Call kernel to get current program break
    mov edx, eax              ; Save current program break in edx

    ; Set the program break to the address to free
    mov eax, 45               ; sys_brk system call number
    mov ebx, ecx              ; Address to set as the new program break (from ecx)
    int 0x80                  ; Call kernel to set new program break

    ; Return
    ret

encrypt_file:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Read the file content into input_buffer
    mov eax, 3                    ; sys_read
    mov ebx, [input_fd]           ; file descriptor
    mov ecx, [input_buffer_addr]  ; input buffer address
    mov edx, [file_size]          ; number of bytes to read
    int 0x80                      ; syscall

    ; Encrypt the data
    push dword [file_size]        ; Number of bytes to process
    push dword [output_buffer_addr] ; Output buffer address
    push dword [input_buffer_addr]  ; Input buffer address
    call encrypt                  ; Call encryption function
    add esp, 12                   ; Clean up stack

    ; Write the encrypted data to the output file
    mov eax, 4                    ; sys_write
    mov ebx, [output_fd]          ; file descriptor
    mov ecx, [output_buffer_addr]      ; output buffer address
    mov edx, [file_size]          ; number of bytes to write
    int 0x80                      ; syscall

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

decrypt_file:
    ; Same as encrypt_file
    call encrypt_file
    ret
