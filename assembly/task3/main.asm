section .data
    prompt_number_msg db 'Enter a number: ', 0
    prompt_number_msg_len equ $-prompt_number_msg
    max_number_msg db 'The maximum value is: ', 0
    max_number_msg_len equ $-max_number_msg
    min_number_msg db 'The minimum value is: ', 0
    min_number_msg_len equ $-min_number_msg
    choice_msg db 'Choose 1 for max, 2 for min: ', 0
    choice_msg_len equ $-choice_msg
    number_str db '%d', 10, 0

section .bss
    num1 resd 1              ; First integer
    num2 resd 1              ; Second integer
    num3 resd 1              ; Third integer
    result resd 1            ; Memory to store the result
    choice resb 2            ; To store user choice (max/min)
    buffer resb 10           ; Buffer to store user input

section .text
    global main
    extern printf

main:
    ; Prompt and read user input for three integers
    call prompt_number        ; Read num1
    mov [num1], eax
    call prompt_number        ; Read num2
    mov [num2], eax
    call prompt_number        ; Read num3
    mov [num3], eax

    ; Prompt user to choose between max or min
    mov eax, 4               ; sys_write
    mov ebx, 1               ; stdout
    mov ecx, choice_msg
    mov edx, choice_msg_len
    int 0x80

    ; Read user choice
    mov eax, 3               ; sys_read
    mov ebx, 0               ; stdin
    mov ecx, choice          ; where to store the input
    mov edx, 2               ; read one byte
    int 0x80

    ; Check the user's choice
    cmp byte [choice], '1'   ; if choice is '1'
    je .find_max
    cmp byte [choice], '2'   ; if choice is '2'
    je .find_min

.find_max:
    push dword [num1]
    push dword [num2]
    push dword [num3]
    call find_max
    add esp, 12
    mov [result], eax

    ; Print "The maximum value is: "
    mov eax, 4               ; sys_write
    mov ebx, 1               ; stdout
    mov ecx, max_number_msg
    mov edx, max_number_msg_len
    int 0x80

    push dword [result]
    push number_str
    call printf
    add esp, 8

    jmp .exit

.find_min:
    push dword [num1]
    push dword [num2]
    push dword [num3]
    call find_min
    add esp, 12
    mov [result], eax

    ; Print "The minimum value is: "
    mov eax, 4               ; sys_write
    mov ebx, 1               ; stdout
    mov ecx, min_number_msg
    mov edx, min_number_msg_len
    int 0x80

    push dword [result]
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
    ; [ebp+8] - first number
    ; [ebp+12] - second number
    ; [ebp+16] - third number

    push ebp
    mov ebp, esp
    push ebx
    push ecx

    ; Load the integers into registers for max comparison
    mov eax, [ebp+8]
    mov ebx, [ebp+12]
    mov ecx, [ebp+16]

    ; Compare eax (num1) and ebx (num2)
    cmp eax, ebx
    jge .check_third         ; If num1 >= num2, check with num3
    mov eax, ebx             ; Else, eax = num2

.check_third:
    cmp eax, ecx
    jge .done                ; If eax >= num3, store result
    mov eax, ecx             ; Else, eax = num3

.done:
    pop ecx
    pop ebx
    pop ebp
    ret

find_min:
    ; Parameters:
    ; [ebp+8] - first number
    ; [ebp+12] - second number
    ; [ebp+16] - third number

    push ebp
    mov ebp, esp
    push ebx
    push ecx

    ; Load the integers into registers for max comparison
    mov eax, [ebp+8]
    mov ebx, [ebp+12]
    mov ecx, [ebp+16]

    ; Compare eax (num1) and ebx (num2)
    cmp eax, ebx
    jle .check_third         ; If num1 >= num2, check with num3
    mov eax, ebx             ; Else, eax = num2

.check_third:
    cmp eax, ecx
    jle .done                ; If eax >= num3, store result
    mov eax, ecx             ; Else, eax = num3

.done:
    pop ecx
    pop ebx
    pop ebp
    ret

prompt_number:
    push ebx
    push ecx
    push edx
    push esi

    ; Print the prompt
    mov eax, 4               ; sys_write
    mov ebx, 1               ; stdout
    mov ecx, prompt_number_msg
    mov edx, prompt_number_msg_len
    int 0x80

    ; Read input
    mov eax, 3               ; sys_read
    mov ebx, 0               ; stdin
    mov ecx, buffer          ; buffer to store input
    mov edx, 10              ; read up to 10 bytes
    int 0x80

    ; Convert ASCII string to integer
    mov eax, 0               ; clear eax (accumulator)
    mov esi, buffer          ; point esi to start of buffer
.convert_loop:
    movzx ebx, byte [esi]    ; load byte into ebx
    cmp bl, 10               ; check for newline
    je .done                 ; if newline, end conversion
    sub bl, '0'              ; convert ASCII to number
    imul eax, eax, 10        ; multiply eax by 10
    add eax, ebx             ; add the number
    inc esi                  ; move to the next byte
    jmp .convert_loop         ; repeat until newline

.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
