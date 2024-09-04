#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define ARRAY_SIZE 1000000

void fill_array(int *array, int size) {
    srand(time(NULL));
    
    for (int i = 0; i < size; ++i) {
        array[i] = rand() % (size * 2);
    }
}

int sum_array(int *array, int size) {
    if (array == NULL || size <= 0) {
        return 0;
    }

    int sum = 0;
    
    for (int i = 0; i < size; ++i) {
        sum += array[i];
    }
    
    return sum;
}

int sum_array_assembly(int *array, int size) {
    if (array == NULL || size <= 0) {
        return 0;
    }

    int sum = 0;

    __asm__ __volatile__ (
        "xorl %%eax, %%eax;"          // Clear eax to use as the accumulator for the sum
        "xorl %%ecx, %%ecx;"          // Clear ecx to use as the index
        "jmp check_condition;"        // Jump to the condition check to start the loop
        "loop_start:;"                // Label for the start of the loop
        "addl (%%ebx, %%ecx, 4), %%eax;" // Add array[ecx] to eax
        "incl %%ecx;"                 // Increment the index
        "check_condition:;"           // Label for the condition check
        "cmpl %%ecx, %%edx;"          // Compare index with array size
        "jne loop_start;"             // Jump to loop_start if ecx is not equal to edx
        "movl %%eax, %0;"             // Move the result from eax to the sum variable
        : "=r"(sum)
        : "b"(array), "d"(size)
        : "%eax", "%ecx"
    );

    return sum;
}

int sum_array_assembly_loop_unrolling(int *array, int size) {
    if (array == NULL || size <= 0) {
        return 0;
    }

    int sum = 0;

    __asm__ __volatile__ (
        "xorl %%eax, %%eax;"           // eax = 0 (initialize sum)
        "movl %%ecx, %%edx;"           // edx = ecx (loop counter)
        "shrl $2, %%edx;"              // edx = edx / 4 (number of 4-element groups)
        "testl %%edx, %%edx;"          // Test if we have more groups
        "jz handle_remainder;"         // Jump to handle_remainder if zero

        "unrolled_loop_start:" 
        "addl (%%ebx), %%eax;"         // Load element 1
        "addl 4(%%ebx), %%eax;"        // Add element 2
        "addl 8(%%ebx), %%eax;"        // Add element 3
        "addl 12(%%ebx), %%eax;"       // Add element 4
        "addl $16, %%ebx;"             // Move to the next 4 elements
        "decl %%edx;"                  // Decrease the counter
        "jnz unrolled_loop_start;"     // Repeat loop if edx != 0

        "handle_remainder:" 
        "andl $3, %%ecx;"              // Get the remainder (number of remaining integers)
        "testl %%ecx, %%ecx;"          // Test if there are remaining elements
        "jz exit;"                     // Jump to exit if zero

        "remaining_loop:" 
        "addl (%%ebx), %%eax;"         // Add element to sum
        "addl $4, %%ebx;"              // Move to the next element
        "decl %%ecx;"                  // Decrease the count
        "jnz remaining_loop;"          // Repeat loop if ecx != 0

        "exit:" 
        "movl %%eax, %0;"              // Store the final sum
        : "=r" (sum)
        : "b" (array), "c" (size)
        : 
    );

    return sum;
}

int find_max_value(int *array, int size) {
    if (array == NULL || size <= 0) {
        return 0;
    }

    int max = array[0];
    
    for (int i = 1; i < size; ++i) {
        if (array[i] > max) {
            max = array[i];
        }
    }

    return max;
}

int find_max_value_assembly(int *array, int size) {
    if (array == NULL || size <= 0) {
        return 0;
    }

    int max_value = 0;

    __asm__ __volatile__ (
        "movl (%%ebx), %%eax;"     // Initialize max to array[0]
        "xorl %%ecx, %%ecx;"       // Clear index
        "jmp check_max_condition;"
        
        "loop_max_start:"
        "movl (%%ebx, %%ecx, 4), %%esi;"  // Load array[ecx] into esi
        "cmpl %%eax, %%esi;"       // Compare max with array[ecx]
        "jle continue_loop_max;"   // Jump if max >= array[ecx]
        
        "movl %%esi, %%eax;"       // Update max if array[ecx] > max
        
        "continue_loop_max:"
        "incl %%ecx;"              // Increment index
        
        "check_max_condition:"
        "cmpl %%ecx, %%edx;"       // Compare index to size
        "jne loop_max_start;"      // Repeat loop
        
        "movl %%eax, %0;"          // Move max value to output variable
        : "=r"(max_value)
        : "b"(array), "d"(size)
        : "%eax", "%ecx", "%esi"
    );

    return max_value;
}

int dot_product(int *array1, int *array2, int size) {
    if (array1 == NULL || array2 == NULL || size <= 0) {
        return 0;
    }

    int dot_product = 0;
    
    for (int i = 0; i < size; ++i) {
        dot_product += array1[i] * array2[i];
    }

    return dot_product;
}

int dot_product_assembly(int *array1, int *array2, int size) {
    if (array1 == NULL || array2 == NULL || size <= 0) {
        return 0;
    }

    int dot_product = 0;

    __asm__ __volatile__ (
        "xorl %%eax, %%eax;"       // Clear eax to use as the accumulator for the dot product
        "xorl %%ecx, %%ecx;"       // Clear index
        "jmp check_dot_condition;" // Jump to the condition check to start the loop

        "loop_dot_start:"
        "movl (%%ebx, %%ecx, 4), %%esi;"  // Load array1[ecx] into esi
        "imull (%%edi, %%ecx, 4), %%esi;" // Multiply array1[ecx] with array2[ecx]
        "addl %%esi, %%eax;"       // Add result to dot product
        "incl %%ecx;"              // Increment index

        "check_dot_condition:"
        "cmpl %%ecx, %%edx;"       // Compare index to size
        "jne loop_dot_start;"        // If ecx >= size, end loop

        "movl %%eax, %0;"          // Move result to output variable
        : "=r"(dot_product)
        : "b"(array1), "D"(array2), "d"(size)
        : "%eax", "%ecx", "%esi"
    );

    return dot_product;
}

int main() {
    int *array1, *array2;
    int sum, max_value, dot_product_result;
    clock_t start, end;
    double cpu_time_used;

    // Allocate memory for the arrays
    array1 = (int *)malloc(ARRAY_SIZE * sizeof(int));
    array2 = (int *)malloc(ARRAY_SIZE * sizeof(int));
    if (array1 == NULL || array2 == NULL) {
        printf("Memory allocation failed\n");
        return 1;
    }

    fill_array(array1, ARRAY_SIZE);
    fill_array(array2, ARRAY_SIZE);

    // Sum array (C version)
    start = clock();
    sum = sum_array(array1, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Sum (C version): %d, Time taken: %f seconds\n", sum, cpu_time_used);

    // Sum array (Assembly version)
    start = clock();
    sum = sum_array_assembly(array1, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Sum (Assembly version): %d, Time taken: %f seconds\n", sum, cpu_time_used);

    // Sum array with loop unrolling (Assembly version)
    start = clock();
    sum = sum_array_assembly_loop_unrolling(array1, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Sum with loop unrolling (Assembly version): %d, Time taken: %f seconds\n", sum, cpu_time_used);

    // Find maximum value (C version)
    start = clock();
    max_value = find_max_value(array1, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Max value (C version): %d, Time taken: %f seconds\n", max_value, cpu_time_used);

    // Find maximum value (Assembly version)
    start = clock();
    max_value = find_max_value_assembly(array1, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Max value (Assembly version): %d, Time taken: %f seconds\n", max_value, cpu_time_used);

    // Dot product (C version)
    start = clock();
    dot_product_result = dot_product(array1, array2, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Dot product (C version): %d, Time taken: %f seconds\n", dot_product_result, cpu_time_used);

    // Dot product (Assembly version)
    start = clock();
    dot_product_result = dot_product_assembly(array1, array2, ARRAY_SIZE);
    end = clock();
    cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
    printf("Dot product (Assembly version): %d, Time taken: %f seconds\n", dot_product_result, cpu_time_used);

    // Free allocated memory
    free(array1);
    free(array2);

    return 0;
}
