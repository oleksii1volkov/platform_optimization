section .data
    array dd 10, 20, 5, 90, 0, 25, 60, 40, 15, 35
    array_len equ ($-array) / 4
    result dd 0
    choice_msg db 'Enter 1 for max, 2 for min: ', 0
    choice_msg_len equ $-choice_msg
    max_number_msg db 'Maximum number: ', 0
    max_number_msg_len equ $-max_number_msg
    min_number_msg db 'Minimum number: ', 0
    min_number_msg_len equ $-min_number_msg
    number_str db '%d', 10, 0

section .bss
    choice resb 2

section .text
    global main
    extern printf

main:
    ; Display prompt and get user choice
    mov eax, 4                  ; syscall: write
    mov ebx, 1                  ; file descriptor: stdout
    mov ecx, choice_msg         ; message to display
    mov edx, choice_msg_len     ; message length
    int 0x80

    ; Read user input
    mov eax, 3              ; syscall: read
    mov ebx, 0              ; file descriptor: stdin
    mov ecx, choice         ; store input in choice
    mov edx, 2              ; read two bytes
    int 0x80

.find_min_or_max:
    cmp byte [choice], '1'
    je .find_max
    cmp byte [choice], '2'
    je .find_min
    jmp .exit

.find_max:
    push array_len
    push array
    call find_max
    add esp, 8
    mov [result], eax

    mov eax, 4                      ; syscall: write
    mov ebx, 1                      ; file descriptor: stdout
    mov ecx, max_number_msg         ; Display "Maximum number: "
    mov edx, max_number_msg_len
    int 0x80

    jmp .display_number
    
.find_min:
    push array_len
    push array
    call find_min
    add esp, 8
    mov [result], eax

    mov eax, 4                      ; syscall: write
    mov ebx, 1                      ; file descriptor: stdout
    mov ecx, min_number_msg         ; Display "Minimum number: "
    mov edx, min_number_msg_len
    int 0x80

    jmp .display_number

.display_number:
    mov eax, [result]               ; Load the result
    push eax
    push number_str
    call printf
    add esp, 8

.exit:
    ; Exit the program
    mov eax, 1               ; sys_exit
    xor ebx, ebx             ; status 0
    int 0x80

find_max:
    ; Parameters:
    ; [ebp+8] - address of the array
    ; [ebp+12] - array length
    
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi

    mov esi, [ebp+8]         ; ESI points to the start of the array
    
    mov eax, [ebp+12]        ; ECX stores the length of the array
    xor edx, edx             ; Zero out EDX
    mov ecx, 4               ; Set ECX to 4
    idiv ecx                 ; Divide the length by 4
    mov ecx, eax             ; Store the quotient in ECX
    mov ebx, edx             ; Store the remainder in EBX
    
    mov eax, [esi]           ; EAX stores the first element of the array (initial value)
    mov edx, eax             ; Store initial value in EDX

.loop_unrolled:
    mov eax, [esi]           ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmova edx, eax           ; Update max if needed
    
    mov eax, [esi+4]         ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmova edx, eax           ; Update max if needed

    mov eax, [esi+8]         ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmova edx, eax           ; Update max if needed

    mov eax, [esi+12]        ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmova edx, eax           ; Update max if needed

    add esi, 16              ; Move to the next element
    loop .loop_unrolled      ; Repeat until all elements are processed

    mov ecx, ebx             ; Set ECX to the remainder

.remainder_loop:
    mov eax, [esi]           ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmova edx, eax           ; Update max if needed

    add esi, 4               ; Move to the next element
    loop .remainder_loop     ; Repeat until all elements are processed

.done:
    mov eax, edx
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

find_min:
    ; Parameters:
    ; [ebp+8] - address of the array
    ; [ebp+12] - array length
    
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi

    mov esi, [ebp+8]         ; ESI points to the start of the array
    
    mov eax, [ebp+12]        ; ECX stores the length of the array
    xor edx, edx             ; Zero out EDX
    mov ecx, 4               ; Set ECX to 4
    idiv ecx                 ; Divide the length by 4
    mov ecx, eax             ; Store the quotient in ECX
    mov ebx, edx             ; Store the remainder in EBX
    
    mov eax, [esi]           ; EAX stores the first element of the array (initial value)
    mov edx, eax             ; Store initial value in EDX

.loop_unrolled:
    mov eax, [esi]           ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmovb edx, eax           ; Update max if needed
    
    mov eax, [esi+4]         ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmovb edx, eax           ; Update max if needed

    mov eax, [esi+8]         ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmovb edx, eax           ; Update max if needed

    mov eax, [esi+12]        ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmovb edx, eax           ; Update max if needed

    add esi, 16              ; Move to the next element
    loop .loop_unrolled      ; Repeat until all elements are processed

    mov ecx, ebx             ; Set ECX to the remainder

.remainder_loop:
    mov eax, [esi]           ; Load the current element into AL
    cmp eax, edx             ; Compare with current max
    cmovb edx, eax           ; Update max if needed

    add esi, 4               ; Move to the next element
    loop .remainder_loop     ; Repeat until all elements are processed

.done:
    mov eax, edx
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret
