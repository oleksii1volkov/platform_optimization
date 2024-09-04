section .data
    prompt_num1 db "Enter first integer: ", 0
    prompt_num1_len equ $ - prompt_num1
    prompt_num2 db "Enter second integer: ", 0
    prompt_num2_len equ $ - prompt_num2
    prompt_op db "Enter operation (+ - * /): ", 0
    prompt_op_len equ $ - prompt_op
    prompt_retry_msg db "Do you want to perform another calculation? (y/n): ", 0
    prompt_retry_msg_len equ $ - prompt_retry_msg
    result_msg db "Result: ", 0
    result_msg_len equ $ - result_msg
    zero_division_msg db "Error: Division by zero", 10, 0
    zero_division_msg_len equ $ - zero_division_msg
    invalid_op_msg db "Error: Invalid operation", 10, 0
    invalid_op_msg_len equ $ - invalid_op_msg
    buffer_len equ 10
    buffer db buffer_len dup(0)
    newline db 10
    char_fmt db '%c', 0
    number_fmt db '%d', 0

section .bss
    num1 resd 1
    num2 resd 1
    result resd 1
    op resb 1

section .text
    global main
    extern printf
    extern fflush

main:
.main_loop:
    ; Prompt for first integer
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, prompt_num1
    mov edx, prompt_num1_len
    int 0x80

    ; Read first integer
    call read_input
    call str_to_int
    mov [num1], eax    ; Store first integer

    ; Prompt for second integer
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, prompt_num2
    mov edx, prompt_num2_len
    int 0x80

    ; Read second integer
    call read_input
    call str_to_int
    mov [num2], eax    ; Store second integer

    ; Prompt for operation
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, prompt_op
    mov edx, prompt_op_len
    int 0x80

    ; ; Read operation
    call read_input
    mov al, [buffer]   ; Load the first byte from buffer into AL
    mov [op], al       ; Store the byte from AL into op

.validate_input:
    mov al, [op]
    cmp al, '+'
    je .operation
    cmp al, '-'
    je .operation
    cmp al, '*'
    je .operation
    cmp al, '/'
    je .check_non_zero

    ; Display invalid operation message
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, invalid_op_msg
    mov edx, invalid_op_msg_len
    int 0x80

    jmp .ask_retry

.check_non_zero:
    mov eax, [num2]
    test eax, eax
    jnz .operation

    ; Display zero division message
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, zero_division_msg
    mov edx, zero_division_msg_len
    int 0x80
    
    jmp .ask_retry

.operation:
    mov al, [op]      ; Load the operation character from 'op' into AL

    cmp al, '+'       ; Compare AL with '+'
    je .add_numbers    ; If equal, jump to add_numbers

    cmp al, '-'       ; Compare AL with '-'
    je .sub_numbers    ; If equal, jump to sub_numbers

    cmp al, '*'       ; Compare AL with '*'
    je .mul_numbers    ; If equal, jump to mul_numbers

    cmp al, '/'       ; Compare AL with '/'
    je .div_numbers    ; If equal, jump to div_numbers

.add_numbers:
    call add_numbers    ; Call the add_numbers function
    jmp .print_result   ; Jump to print_result after the addition

.sub_numbers:
    call sub_numbers    ; Call the sub_numbers function
    jmp .print_result   ; Jump to print_result after the subtraction

.mul_numbers:
    call mul_numbers    ; Call the mul_numbers function
    jmp .print_result   ; Jump to print_result after the multiplication

.div_numbers:
    call div_numbers    ; Call the div_numbers function
    jmp .print_result   ; Jump to print_result after the division

.print_result:
    ; Store result
    mov [result], eax

    ; Display result message
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, result_msg
    mov edx, result_msg_len
    int 0x80

    mov eax, [result]
    push eax
    call print_number
    add esp, 4

    push dword [newline]
    call print_char
    add esp, 4

.ask_retry:
    mov eax, 4         ; sys_write
    mov ebx, 1         ; file descriptor (stdout)
    mov ecx, prompt_retry_msg
    mov edx, prompt_retry_msg_len
    int 0x80

    ; Read user response
    call read_input
    
    mov  al, [buffer]
    cmp al, 'y'
    je .main_loop
    cmp al, 'Y'
    je .main_loop

    ; Exit
    mov eax, 1         ; sys_exit
    xor ebx, ebx       ; Exit code 0
    int 0x80

add_numbers:
    mov eax, [num1]
    add eax, [num2]
    ret

sub_numbers:
    mov eax, [num1]
    sub eax, [num2]
    ret

mul_numbers:
    mov eax, [num1]
    imul eax, [num2]
    ret

div_numbers:
    mov eax, [num1]
    mov ebx, [num2]
    xor edx, edx
    div ebx
    ret

read_input:
    mov eax, 3         ; sys_read
    mov ebx, 0         ; file descriptor (stdin)
    mov ecx, buffer
    mov edx, buffer_len
    int 0x80
    ret

str_to_int:
    ; Parameters:
    ; [ebp+8] - pointer to string

    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx

    mov ecx, buffer
    xor eax, eax
    xor ebx, ebx
    mov bl, 10         ; Base 10
.convert_loop:
    movzx edx, byte [ecx]
    cmp edx, 10
    je .done
    sub edx, '0'
    imul eax, ebx
    add eax, edx
    inc ecx
    jmp .convert_loop
.done:
    pop edx
    pop ecx
    pop ebx
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
