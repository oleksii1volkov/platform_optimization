section .data
    expr db '21 + 34 - 2 + 10', 0          ; The arithmetic expression as a string
    expr_len equ $ - expr
    rpn_expr_len equ expr_len * 2
    expression_msg db 'Expression: ', 0
    expression_msg_len equ $ - expression_msg
    result_msg db 'Result: ', 0
    result_msg_len equ $ - result_msg
    error_msg db 'Syntax Error', 0
    error_msg_len equ $ - error_msg
    space db ' '
    newline db 10
    number_fmt db '%d', 0
    char_fmt db '%c', 0
    str_fmt db '%s', 0

section .bss
    stack resd 128                   ; Stack for operators
    stack_pointer resd 1             ; Stack pointer (index in stack)
    rpn_expr resb rpn_expr_len       ; Buffer to store the RPN output
    result resd 1

section .text
    global main
    extern printf
    extern fflush

main:
    push expression_msg
    push str_fmt
    call print_format
    add esp, 8

    push expr
    push str_fmt
    call print_format
    add esp, 8

    push dword [newline]
    push char_fmt
    call print_format
    add esp, 8

    ; Initialize stack pointer
    mov dword [stack_pointer], 0
    ; Initialize RPN expression buffer
    mov byte [rpn_expr], 0
    
    ; Convert the infix expression to RPN
    call convert_to_rpn

    cmp eax, 0
    jne .syntax_error
    jmp .calculate_rpn

.syntax_error:
    push error_msg
    push str_fmt
    call print_format
    add esp, 8

    jmp .exit

.calculate_rpn:
    ; Initialize stack pointer
    mov dword [stack_pointer], 0
    
    ; Calculate the result of the RPN expression
    call calculate_rpn
    mov [result], eax
    
    push result_msg
    push str_fmt
    call print_format
    add esp, 8

    ; Print the result
    push dword [result]
    push number_fmt
    call print_format
    add esp, 8
    
    ; Print a newline character
    push dword [newline]
    push char_fmt
    call print_format
    add esp, 4

.exit:
    ; Exit the program
    mov eax, 1                      ; sys_exit
    xor ebx, ebx                    ; Exit code 0
    int 0x80

convert_to_rpn:
    push ebx
    push ecx
    push edx

    xor ecx, ecx                     ; Index for expr
    xor ebx, ebx                     ; Initialize number accumulator to 0
    xor edx, edx                     ; Initialize current operator to 0

.parse_expr:
    mov al, [expr + ecx]             ; Load the current character
    cmp al, 0                        ; Check if we reached the end of the string
    je .end_parse                    ; End of string, output remaining operators

    ; Skip whitespace
    cmp al, ' '
    je .next_char
    
    ; Check if the character is a digit
    cmp al, '0'
    jl .check_operator
    cmp al, '9'
    jg .check_operator

    ; It's a digit, accumulate the number
    cmp ebx, 0
    jne .syntax_error                ; Previous token was a number, syntax error
    
    push expr
    call parse_number
    add esp, 4
    mov ebx, eax
    xor edx, edx                     ; Clear current operator
    jmp .next_char

.check_operator:
    cmp edx, 0
    jne .syntax_error                ; Previous character was an operator, syntax error

    push ebx
    push rpn_expr
    call append_number
    add esp, 8

    push dword [space]
    push rpn_expr
    call append_char
    add esp, 8

    movzx edx, al                    ; Store the current operator in edx

    ; Handle operators
    cmp al, '+'
    je .handle_operator
    cmp al, '-'
    je .handle_operator
    jmp .syntax_error

.handle_operator:
    ; Pop operators from stack to output if they have the same precedence
    call stack_top
    cmp eax, 0xFFFFFFFF
    je .push_operator                ; Stack is empty, push operator

    ; Pop operator from stack to output
    call stack_pop

    push eax
    push rpn_expr
    call append_char
    add esp, 8

    push dword [space]
    push rpn_expr
    call append_char
    add esp, 8

.push_operator:
    push edx                         ; Store the operator
    call stack_push
    add esp, 4

    xor ebx, ebx                     ; Reset the number accumulator
    jmp .next_char

.next_char:
    inc ecx
    jmp .parse_expr

.end_parse:
    ; Output the last accumulated number
    cmp edx, 0
    jne .syntax_error

    push ebx
    push rpn_expr
    call append_number
    add esp, 8

    push dword [space]
    push rpn_expr
    call append_char
    add esp, 8

.pop_operators:
    ; Pop all operators from stack to output
    call stack_pop
    cmp eax, 0xFFFFFFFF
    je .success

    push eax
    push rpn_expr
    call append_char
    add esp, 8

    push dword [space]
    push rpn_expr
    call append_char
    add esp, 8

    jmp .pop_operators

.syntax_error:
    mov eax, 1
    jmp .done

.success:
    xor eax, eax

.done:
    pop edx
    pop ecx
    pop ebx
    ret

calculate_rpn:
    push ebx
    push ecx

    mov ecx, 0                   ; Initialize the index for rpn_expr

.next_token:
    mov al, [rpn_expr + ecx]
    cmp al, 0
    je .done
    
    ; Skip whitespace
    cmp al, ' '
    je .skip_whitespace

    ; Check if the character is a digit
    cmp al, '0'
    jl .check_operator
    cmp al, '9'
    jg .check_operator

    ; It's a digit, parse the full number
    push rpn_expr
    call parse_number
    add esp, 4
    push eax
    call stack_push
    add esp, 4
    jmp .next_char

.check_operator:
    ; If it's an operator, perform the operation
    cmp al, '+'
    je .handle_addition
    cmp al, '-'
    je .handle_subtraction
    jmp .done

.handle_addition:
    ; Pop two operands and add them
    call stack_pop               ; Pop first operand
    mov ebx, eax                 ; Store it in ebx
    call stack_pop               ; Pop second operand
    add eax, ebx                 ; Add the two operands
    push eax                     ; Push the result
    call stack_push              ; Push the result back onto the stack
    add esp, 4
    jmp .next_char

.handle_subtraction:
    ; Pop two operands and subtract them
    call stack_pop               ; Pop first operand
    mov ebx, eax                 ; Store it in ebx
    call stack_pop               ; Pop second operand
    sub eax, ebx                 ; Subtract the two operands
    push eax                     ; Push the result
    call stack_push              ; Push the result back onto the stack
    add esp, 4
    jmp .next_char

.skip_whitespace:
    jmp .next_char

.next_char:
    inc ecx
    jmp .next_token

.done:
    ; The final result should be on top of the stack
    call stack_pop
   
    pop ecx
    pop ebx
    ret

parse_number:
    ; Parameters:
    ; [ebp+8] - address of the string
    ; ecx - index into the string

    push ebp
    mov ebp, esp
    push ebx
    push esi

    mov esi, [ebp+8]
    xor eax, eax                 ; Clear eax (this will hold the number)
    xor ebx, ebx                 ; Clear ebx (this will hold the current digit)
.parse_loop:
    mov bl, [esi + ecx]
    cmp bl, '0'
    jl .end_parse
    cmp bl, '9'
    jg .end_parse
    sub bl, '0'                  ; Convert ASCII to integer
    imul eax, eax, 10            ; Multiply current number by 10
    add eax, ebx                 ; Add the new digit
    inc ecx                      ; Move to the next character
    jmp .parse_loop

.end_parse:
    dec ecx                      ; Adjust index back after the loop
    
    pop esi
    pop ebx
    pop ebp
    ret

stack_push:
    push ebp
    mov ebp, esp
    push eax
    push ebx

    mov ebx, [stack_pointer]
    inc ebx
    mov [stack_pointer], ebx
    mov eax, [ebp + 8]
    mov [stack + ebx*4 - 4], eax
    
    pop ebx
    pop eax
    pop ebp
    ret

stack_pop:
    push ebx

    mov ebx, [stack_pointer]
    cmp ebx, 0
    je .stack_underflow
    mov eax, [stack + ebx*4 - 4]
    dec ebx
    mov [stack_pointer], ebx
    jmp .done

.stack_underflow:
    mov eax, 0xFFFFFFFF                 ; Invalid operator (underflow)

.done:
    pop ebx
    ret

stack_top:
    push ebx

    mov ebx, [stack_pointer]
    cmp ebx, 0
    je .stack_empty
    mov eax, [stack + ebx*4 - 4]
    jmp .done

.stack_empty:
    mov eax, 0xFFFFFFFF                 ; Invalid operator (empty stack)
    
.done:
    pop ebx
    ret

append_char:
    ; Parameters:
    ; [ebp+8] - address of the string
    ; [ebp+12] - character to append

    push ebp
    mov ebp, esp
    push eax
    push esi

    mov esi, [ebp+8]        ; Load the address of the string into ESI
    mov eax, [ebp+12]       ; Load the character to append into EAX

    ; Find the null terminator in the string
.find_end:
    cmp byte [esi], 0      ; Compare current byte with null terminator
    je .write_char          ; If it's null, we've found the end
    inc esi                ; Move to the next byte
    jmp .find_end           ; Repeat until the end is found

    ; Write the character and the new null terminator
.write_char:
    mov [esi], al          ; Write the new character at the end
    inc esi                ; Move to the next position
    mov byte [esi], 0      ; Write the new null terminator
    
    pop esi
    pop eax
    pop ebp
    ret

append_number:
    ; Parameters:
    ; [ebp+8] - address of the string
    ; [ebp+12] - number to print

    push ebp
    mov ebp, esp
    push eax             ; Save registers that will be modified
    push ebx
    push ecx
    push edx

    mov eax, [ebp+12]    ; The number to append
    mov ecx, 10          ; Divisor for modulus (base 10)
    xor ebx, ebx         ; Clear EBX (used for digit count)

.loop:
    xor edx, edx         ; Clear EDX before division
    div ecx              ; Divide EAX by 10, EAX = quotient, EDX = remainder
    add dl, '0'          ; Convert remainder to ASCII
    push edx             ; Push digit onto stack
    inc ebx              ; Increment digit count
    test eax, eax        ; Check if the quotient is 0
    jnz .loop            ; If not, continue loop

.append_loop:
    push dword [ebp+8]
    call append_char     ; Print the digit
    add esp, 8           ; Clean up stack
    dec ebx              ; Decrement digit count
    jnz .append_loop     ; If there are more digits, continue appending

    pop edx              ; Restore modified registers
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

get_string_length:
    ; Parameters
    ; [ebp+8] - address of the string

    push ebp
    mov ebp, esp
    push ebx
    push esi

    xor eax, eax
    mov esi, [ebp+8]

.loop:
    mov bl, [esi]
    cmp bl, 0
    je .done
    inc eax
    inc esi
    jmp .loop

.done:
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
