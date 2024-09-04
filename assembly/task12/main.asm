section .data
    first_array_msg db "First array: ", 0
    first_array_msg_len equ $ - first_array_msg
    second_array_msg db "Second array: ", 0
    second_array_msg_len equ $ - second_array_msg
    common_array_msg db "Common elements: ", 0
    common_array_msg_len equ $ - common_array_msg
    unique_array1_msg db "Unique elements of the first array: ", 0
    unique_array1_msg_len equ $ - unique_array1_msg
    unique_array2_msg db "Unique elements of the second array: ", 0
    unique_array2_msg_len equ $ - unique_array2_msg
    array1_size equ 10
    array2_size equ 10
    newline db 10
    space db " "
    num_fmt db "%d", 0
    char_fmt db "%c", 0
    str_fmt db "%s", 0

section .bss
    array1_addr resd 1
    array2_addr resd 1
    common_array_addr resd 1
    common_array_size resd 1
    unique_array1_addr resd 1
    unique_array1_size resd 1
    unique_array2_addr resd 1
    unique_array2_size resd 1

section .text
    global main
    extern printf
    extern fflush

main:
    ; Allocate memory for arrays
    mov ecx, array1_size * 4
    call allocate_memory
    mov [array1_addr], eax
    
    mov ecx, array2_size * 4
    call allocate_memory
    mov [array2_addr], eax
    
    ; Populate arrays
    push dword 4
    push array1_size
    push dword [array1_addr]
    call populate_array
    add esp, 12

    push dword 5
    push array2_size
    push dword [array2_addr]
    call populate_array
    add esp, 12

    ; Perform set operations
    
    ; Get common array size
    push array1_size
    push array2_size
    call get_min_number
    add esp, 8
    mov [common_array_size], eax

    ; Allocate memory for common array
    mov eax, [common_array_size]
    imul eax, 4
    mov ecx, eax
    call allocate_memory
    mov [common_array_addr], eax

    ; Find common elements
    push dword [common_array_size]
    push dword [common_array_addr]
    push array2_size
    push dword [array2_addr]
    push array1_size
    push dword [array1_addr]
    call find_common_elements
    add esp, 24
    mov [common_array_size], eax

    ; Get unique array 1 size
    push array1_size
    push array1_size
    call get_max_number
    add esp, 8
    mov [unique_array1_size], eax

    ; Allocate memory for unique array 1
    mov eax, [unique_array1_size]
    imul eax, 4
    mov ecx, eax
    call allocate_memory
    mov [unique_array1_addr], eax

    ; Find unique elements
    push dword [unique_array1_size]
    push dword [unique_array1_addr]
    push array2_size
    push dword [array2_addr]
    push array1_size
    push dword [array1_addr]
    call find_unique_elements
    add esp, 24
    mov [unique_array1_size], eax

    ; Get unique array 2 size
    push array1_size
    push array1_size
    call get_max_number
    add esp, 8
    mov [unique_array2_size], eax

    ; Allocate memory for unique array 1
    mov eax, [unique_array2_size]
    imul eax, 4
    mov ecx, eax
    call allocate_memory
    mov [unique_array2_addr], eax

    ; Find unique elements
    push dword [unique_array2_size]
    push dword [unique_array2_addr]
    push array1_size
    push dword [array1_addr]
    push array2_size
    push dword [array2_addr]
    call find_unique_elements
    add esp, 24
    mov [unique_array2_size], eax

    ; Output results

    ; Print first array
    push first_array_msg
    push str_fmt
    call print_format
    add esp, 8
    
    push array1_size
    push dword [array1_addr]
    call print_array
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Print second array
    push second_array_msg
    push str_fmt
    call print_format
    add esp, 8

    push array2_size
    push dword [array2_addr]
    call print_array
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Print common array
    push common_array_msg
    push str_fmt
    call print_format
    add esp, 8

    push dword [common_array_size]
    push dword [common_array_addr]
    call print_array
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Print unique array 1
    push unique_array1_msg
    push str_fmt
    call print_format
    add esp, 8

    push dword [unique_array1_size]
    push dword [unique_array1_addr]
    call print_array
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Print unique array 2
    push unique_array2_msg
    push str_fmt
    call print_format
    add esp, 8

    push dword [unique_array2_size]
    push dword [unique_array2_addr]
    call print_array
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Free memory
    mov ecx, [unique_array2_addr]
    call free_memory

    mov ecx, [unique_array1_addr]
    call free_memory

    mov ecx, [common_array_addr]
    call free_memory

    mov ecx, [array2_addr]
    call free_memory

    mov ecx, [array1_addr]
    call free_memory
    
    ; Exit program
    mov eax, 1                ; sys_exit
    xor ebx, ebx              ; status 0
    int 0x80

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

populate_array:
    ; Parameters:
    ; [ebp+8] - Address of the array
    ; [ebp+12] - Number of elements in the array
    ; [ebp+16] - n (skip factor)

    ; Local variables:
    ; eax - Current number to add to the array
    ; ebx - Counter for skipping every nth number

    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push esi

    mov esi, [ebp+8]     ; Point ESI to the start of the array
    mov ecx, [ebp+12]    ; Number of elements in the array
    mov edx, [ebp+16]    ; n (skip factor)

    xor eax, eax        ; Initialize eax to 0 (will start at 1 after increment)
    xor ebx, ebx        ; Initialize skip counter

.populate_loop:
    add eax, 1          ; Increment current number
    inc ebx             ; Increment skip counter

    cmp ebx, edx        ; Compare skip counter with n (skip factor)
    je .skip_number     ; If equal, skip this number and reset skip counter

    mov [esi], eax      ; Store the current number in the array
    add esi, 4          ; Move to the next element in the array
    dec ecx             ; Decrement the element count
    jz .done            ; If ecx reaches 0, we are done

    jmp .populate_loop  ; Continue populating the array

.skip_number:
    xor ebx, ebx        ; Reset skip counter
    jmp .populate_loop  ; Skip the current number and continue

.done:
    pop esi
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

find_common_elements:
    ; Stack parameters (passed in the following order):
    ; [ebp+8]  - Address of the first array
    ; [ebp+12] - Size of the first array (number of elements)
    ; [ebp+16] - Address of the second array
    ; [ebp+20] - Size of the second array (number of elements)
    ; [ebp+24] - Address of the common array
    ; [ebp+28] - Size of the common array (number of elements)

    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov esi, [ebp+8]          ; Load the address of the first array
    mov ecx, [ebp+12]         ; Load the size of the first array
    mov edi, [ebp+24]         ; Load the address of the common array

    ; Clear the common array size
    xor ebx, ebx              ; EBX will store the size of the common array

    ; Loop through the first array
.outer_loop:
    mov eax, [esi]            ; Load the current element from the first array
    push ecx                  ; Save the outer loop counter
    push esi                  ; Save ESI
    mov esi, [ebp+16]         ; Set ESI to the start of the second array
    mov ecx, [ebp+20]         ; Load size of the second array

    ; Loop through the second array
.inner_loop:
    mov edx, [esi]            ; Load the current element from the second array
    cmp eax, edx              ; Compare elements
    jne .continue_inner       ; If not equal, continue

    ; Store the common element
    mov [edi+ebx*4], eax      ; Store the common element
    inc ebx                   ; Increment the number of common elements
    jmp .continue_outer       ; Exit inner loop

.continue_inner:
    add esi, 4                ; Move to the next element in the second array
    loop .inner_loop          ; Continue the inner loop

.continue_outer:
    pop esi                   ; Restore ESI
    pop ecx                   ; Restore the outer loop counter
    add esi, 4                ; Move to the next element in the first array
    loop .outer_loop          ; Continue the outer loop

    ; Return
    mov eax, ebx              ; Return the number of common elements
    
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret
    
find_unique_elements:
    ; Stack parameters:
    ; [ebp+8]  - Address of the first array
    ; [ebp+12] - Size of the first array (number of elements)
    ; [ebp+16] - Address of the second array
    ; [ebp+20] - Size of the second array (number of elements)
    ; [ebp+24] - Address of the unique array
    ; [ebp+28] - Size of the unique array (number of elements)

    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov esi, [ebp+8]          ; Load the address of the first array
    mov ecx, [ebp+12]         ; Load the size of the first array
    mov edi, [ebp+24]         ; Load the address of the unique array

    ; Clear the unique array size
    xor ebx, ebx              ; EBX will store the size of the unique array

    ; Loop through the first array
.outer_loop:
    mov eax, [esi]            ; Load the current element from the first array
    push ecx                  ; Save the outer loop counter
    push esi                  ; Save ESI
    mov esi, [ebp+16]         ; Set ESI to the start of the second array
    mov edx, [ebp+20]         ; Load size of the second array

.inner_loop:
    mov ecx, [esi]            ; Load the current element from the second array
    cmp eax, ecx              ; Compare elements
    je .not_unique            ; If equal, element is not unique

    add esi, 4                ; Move to the next element in the second array
    dec edx                   ; Decrement the counter
    jnz .inner_loop           ; Continue the inner loop if not zero

.unique:
    mov [edi], eax            ; Store the unique element
    add edi, 4                ; Move to the next position in the unique array
    inc ebx                   ; Increment the unique array counter

.not_unique:
    pop esi                   ; Restore ESI
    pop ecx                   ; Restore the outer loop counter
    add esi, 4                ; Move to the next element in the first array
    loop .outer_loop          ; Continue the outer loop

    ; Return the size of the unique array
    mov eax, ebx              ; Return the number of unique elements
    
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

get_min_number:
    ; Stack parameters:
    ; [ebp+8] - First integer
    ; [ebp+12] - Second integer

    push ebp
    mov ebp, esp
    push ebx

    ; Load the two integers from the stack
    mov eax, [ebp+8]         ; Load the first integer into EAX
    mov ebx, [ebp+12]        ; Load the second integer into EBX

    cmp eax, ebx
    jle .return_eax
    
    mov eax, ebx

.return_eax:
    pop ebx
    pop ebp
    ret

get_max_number:
    ; Stack parameters:
    ; [ebp+8] - First integer
    ; [ebp+12] - Second integer

    push ebp
    mov ebp, esp
    push ebx

    mov eax, [ebp+8]         ; Load the first integer into EAX
    mov ebx, [ebp+12]        ; Load the second integer into EBX

    cmp eax, ebx
    jge .return_eax
    
    mov eax, ebx

.return_eax:
    pop ebx
    pop ebp
    ret

print_array:
    ; Parameters:
    ; [ebp+8] - address of the array
    ; [ebp+12] - length of the array

    push ebp
    mov ebp, esp
    push eax
    push ecx
    push esi

    mov esi, [ebp+8]     ; Point ESI to the start of the array
    mov ecx, [ebp+12]    ; Length of the array

.print_loop:
    mov eax, [esi]       ; Load the current element into EAX
    push eax             ; Push the element onto the stack
    push num_fmt
    call print_format    ; Print the number
    add esp, 8           ; Clean up the stack

    ; Print a space after each number
    push dword [space]
    push char_fmt
    call print_format
    add esp, 8

    add esi, 4           ; Move to the next element (4 bytes)
    loop .print_loop     ; Decrement ECX and loop if not zero

    pop esi
    pop ecx
    pop eax
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
