section .data
    array dd 10, 20, 5, 55, 30, 25, 0, 40, 15
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
    movzx eax, byte [choice]
    push eax
    push array_len
    push array
    call find_min_or_max
    add esp, 12
    mov [result], eax

.display_result:
    cmp byte [choice], '1'
    je .display_max
    cmp byte [choice], '2'
    je .display_min
    jmp .exit

.display_max:
    mov eax, 4                      ; syscall: write
    mov ebx, 1                      ; file descriptor: stdout
    mov ecx, max_number_msg         ; Display "Maximum number: "
    mov edx, max_number_msg_len
    int 0x80

    jmp .display_number
    
.display_min:
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

find_min_or_max:
    ; Parameters:
    ; [ebp+8] - address of the array
    ; [ebp+12] - array length
    ; [ebp+16] - 1 for max, 2 for min

    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push esi

    mov esi, [ebp+8]         ; ESI points to the start of the array
    mov ecx, [ebp+12]        ; ECX stores the length of the array
    mov bl, [ebp+16]         ; BL stores the user choice
    mov eax, [esi]           ; EAX stores the first element of the array (initial value)
    mov edx, eax             ; Store initial value in EDX

.loop:
    mov eax, [esi]           ; Load the current element into AL

    ; Compare based on user choice
    cmp bl, '1'              ; If choice is '1', find max
    je .find_max
    cmp bl, '2'              ; If choice is '2', find min
    je .find_min

.find_max:
    cmp eax, edx             ; Compare with current result
    jle .skip                ; If current element is less or equal, skip
    mov edx, eax             ; Otherwise, update result
    jmp .skip

.find_min:
    cmp eax, edx             ; Compare with current result
    jge .skip                ; If current element is greater or equal, skip
    mov edx, eax             ; Otherwise, update result

.skip:
    add esi, 4               ; Move to the next element
    loop .loop               ; Repeat until all elements are processed

.done:
    mov eax, edx
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret
