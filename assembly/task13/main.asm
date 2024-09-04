section .data
    first_operand_msg db "First operand: ", 0
    first_operand_msg_len equ $ - first_operand_msg
    second_operand_msg db "Second operand: ", 0
    second_operand_msg_len equ $ - second_operand_msg
    addition_msg db "Addition: ", 0
    addition_msg_len equ $ - addition_msg
    subtraction_msg db "Subtraction: ", 0
    subtraction_msg_len equ $ - subtraction_msg
    multiplication_msg db "Multiplication: ", 0
    multiplication_msg_len equ $ - multiplication_msg
    division_msg db "Division: ", 0
    division_msg_len equ $ - division_msg
    newline db 10
    num_fmt db "%d", 0
    char_fmt db "%c", 0
    str_fmt db "%s", 0

    operand1 dd 10
    operand2 dd 5
    result   dd 0

section .text
    global main
    extern printf
    extern fflush

    ; Macro Definitions
%macro ADD 2
    mov eax, [%1]           ; Load first operand into eax
    add eax, [%2]           ; Add second operand to eax
    mov [%1], eax           ; Store the result in the first operand location
%endmacro

%macro SUB 2
    mov eax, [%1]           ; Load first operand into eax
    sub eax, [%2]           ; Subtract second operand from eax
    mov [%1], eax           ; Store the result in the first operand location
%endmacro

%macro MUL 2
    mov eax, [%1]           ; Load first operand into eax
    imul dword [%2]         ; Multiply eax by second operand
    mov [%1], eax           ; Store the result in the first operand location
%endmacro

%macro DIV 2
    mov eax, [%1]           ; Load dividend into eax
    xor edx, edx            ; Clear edx (necessary for division)
    idiv dword [%2]         ; Divide eax by the divisor (edx:eax / operand)
    mov [%1], eax           ; Store the quotient in the first operand location
%endmacro

main:
    ; Print operands
    push first_operand_msg
    push dword [operand1]
    call print_label_and_number
    add esp, 12

    push second_operand_msg
    push dword [operand2]
    call print_label_and_number
    add esp, 12

    ; Initialize operand1 with addition result
    push dword [operand1]
    ADD operand1, operand2  ; operand1 = operand1 + operand2

    ; Store the result into 'result' variable
    mov eax, [operand1]
    mov [result], eax
    pop dword [operand1]

    ; Print result (addition)
    push addition_msg
    push dword [result]
    call print_label_and_number
    add esp, 12

    ; Initialize operand1 with subtraction result
    push dword [operand1]
    SUB operand1, operand2  ; operand1 = operand1 - operand2

    ; Store the result into 'result' variable
    mov eax, [operand1]
    mov [result], eax
    pop dword [operand1]

    ; Print result (subtraction)
    push subtraction_msg
    push dword [result]
    call print_label_and_number
    add esp, 12

    ; Initialize operand1 with multiplication result
    push dword [operand1]
    MUL operand1, operand2  ; operand1 = operand1 * operand2

    ; Store the result into 'result' variable
    mov eax, [operand1]
    mov [result], eax
    pop dword [operand1]

    ; Print result (multiplication)
    push multiplication_msg
    push dword [result]
    call print_label_and_number
    add esp, 12

    ; Initialize operand1 with division result
    push dword [operand1]
    DIV operand1, operand2  ; operand1 = operand1 / operand2

    ; Store the result into 'result' variable
    mov eax, [operand1]
    mov [result], eax
    pop dword [operand1]

    ; Print result (division)
    push division_msg
    push dword [result]
    call print_label_and_number
    add esp, 12

    ; Exit the program
    mov eax, 1              ; System call for exit
    xor ebx, ebx            ; Exit code 0
    int 0x80

print_label_and_number:
    ; Parameters:
    ; [ebp+8] - number to print
    ; [ebp+12] - address of the label

    push ebp
    mov ebp, esp

    push dword [ebp+12]
    push str_fmt
    call print_format
    add esp, 8

    push dword [ebp+8]
    push num_fmt
    call print_format
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

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
