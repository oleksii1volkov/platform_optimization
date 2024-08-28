section .data
    unsorted_array dd 6, 5, 4, 3, 2, 1
    array_length equ ($ - unsorted_array) / 4
    sorted_array dd array_length dup(0)
    unsorted_array_msg db 'Unsorted Array: ', 0
    unsorted_array_msg_len equ $ - unsorted_array_msg
    sorted_array_msg db 'Sorted Array: ', 0
    sorted_array_msg_len equ $ - sorted_array_msg
    newline db 10
    space db ' '
    number_fmt db '%d', 0
    char_fmt db '%c', 0
    
section .text
    global main
    extern printf
    extern fflush

main:
    ; Display message
    mov eax, 4
    mov ebx, 1
    mov ecx, unsorted_array_msg
    mov edx, unsorted_array_msg_len
    int 0x80

    ; Print unsorted array
    push array_length
    push unsorted_array
    call print_array
    add esp, 8

    ; Print a newline
    push dword [newline]
    call print_char
    add esp, 4

    ; Copy the unsorted array to the sorted array
    mov ecx, array_length    ; Length of the array
    push ecx                 ; Push the length onto the stack
    mov esi, unsorted_array  ; Source
    mov edi, sorted_array    ; Destination
    rep movsd                ; Copy the array
    pop ecx                  ; Pop the length from the stack

    ; Sort the array using bubble sort
    push array_length
    push sorted_array
    call bubble_sort         ; Call the bubble sort procedure
    add esp, 8

    ; Display message
    mov eax, 4
    mov ebx, 1
    mov ecx, sorted_array_msg
    mov edx, sorted_array_msg_len
    int 0x80

    ; Print sorted array
    push array_length
    push sorted_array
    call print_array
    add esp, 8

    ; Print a newline
    push dword [newline]
    call print_char
    add esp, 4

    ; Exit program
    mov eax, 1               ; syscall: sys_exit
    xor ebx, ebx             ; status: 0
    int 0x80                 ; invoke syscall

bubble_sort:
    ; Parameters:
    ; [ebp+8] - address of the array
    ; [ebp+12] - length of the array
    
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; Load parameters
    mov esi, [ebp+8]   ; esi = address of the array
    mov ecx, [ebp+12]  ; ecx = length of the array
    dec ecx            ; ecx = length - 1 (we will use this as a counter)
    xor ebx, ebx       ; ebx = 0 (we will use this as a swap flag)

.outer_loop:
    mov edi, ecx       ; edi = ecx (remaining length to sort)
    cmp edi, 0
    jle .done          ; if edi <= 0, exit outer loop

.inner_loop:
    mov eax, [esi]        ; eax = array[i]
    mov edx, [esi+4]      ; edx = array[i+1]

    cmp eax, edx          ; compare array[i] and array[i+1]
    jle .skip_swap         ; if array[i] <= array[i+1], skip swap

    ; Swap array[i] and array[i+1]
    mov [esi], edx        ; array[i] = array[i+1]
    mov [esi+4], eax      ; array[i+1] = array[i]
    mov ebx, 1            ; set swap flag

.skip_swap:
    add esi, 4            ; move to the next element
    dec edi               ; decrement inner loop counter
    jnz .inner_loop       ; repeat until end of array

    mov esi, [ebp+8]      ; Reset esi to the start of the array
    dec ecx               ; Decrement outer loop counter

    cmp ebx, 0            ; Check if the swap flag is set
    jne .outer_loop

.done:
    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
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
    call print_number    ; Print the number
    add esp, 4           ; Clean up the stack

    ; Print a space after each number
    push dword [space]
    call print_char
    add esp, 4

    add esi, 4           ; Move to the next element (4 bytes)
    loop .print_loop     ; Decrement ECX and loop if not zero

    pop esi
    pop ecx
    pop eax
    pop ebp
    ret

print_char:
    ; Parameters:
    ; [ebp+8] - charecter to print

    push ebp
    mov ebp, esp
    push ecx
    
    push dword [ebp+8]
    push char_fmt
    call printf
    add esp, 8

    push 0
    call fflush
    add esp, 4

    pop ecx
    pop ebp
    ret

print_number:
    ; Parameters:
    ; [ebp+8] - number to print

    push ebp
    mov ebp, esp
    push ecx
    
    push dword [ebp+8]
    push number_fmt
    call printf
    add esp, 8

    push 0
    call fflush
    add esp, 4

    pop ecx
    pop ebp
    ret
