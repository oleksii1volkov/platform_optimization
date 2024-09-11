#include <chrono>
#include <cstdlib>
#include <cstring>
#include <immintrin.h>
#include <iostream>
#include <memory>
#include <vector>

void *aligned_malloc(size_t size) {
    void *pointer{nullptr};
    posix_memalign(&pointer, 32, size);

    return pointer;
}

void add_vectors_simd(const float *first_array, const float *second_array,
                      float *result_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr ||
        result_array == nullptr) {
        return;
    }

    const size_t simd_width{8};
    const size_t last_vector_index{array_size - (array_size % simd_width)};

    for (size_t vector_index{0}; vector_index < last_vector_index;
         vector_index += simd_width) {
        __m256 first_vector{_mm256_load_ps(&first_array[vector_index])};
        __m256 second_vector{_mm256_load_ps(&second_array[vector_index])};
        __m256 result_vector{_mm256_add_ps(first_vector, second_vector)};
        _mm256_store_ps(&result_array[vector_index], result_vector);
    }

    for (size_t number_index{last_vector_index}; number_index < array_size;
         ++number_index) {
        result_array[number_index] =
            first_array[number_index] + second_array[number_index];
    }
}

void add_vectors_loop(const float *first_array, const float *second_array,
                      float *result_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr ||
        result_array == nullptr) {
        return;
    }

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        result_array[number_index] =
            first_array[number_index] + second_array[number_index];
    }
}

float calculate_dot_product_simd(const float *first_array,
                                 const float *second_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr) {
        return 0.0f;
    }

    const size_t simd_width{8};
    const size_t last_vector_index{array_size - (array_size % simd_width)};
    __m256 sum = _mm256_setzero_ps();

    for (size_t vector_index{0}; vector_index < last_vector_index;
         vector_index += simd_width) {
        __m256 first_vector{_mm256_load_ps(&first_array[vector_index])};
        __m256 second_vector{_mm256_load_ps(&second_array[vector_index])};
        sum = _mm256_add_ps(sum, _mm256_mul_ps(first_vector, second_vector));
    }

    // Sum the elements of the __m256 register
    alignas(32) float result[simd_width]{0.0f};
    _mm256_store_ps(result, sum);
    float dot_product{0.0f};

    for (size_t number_index{0}; number_index < simd_width; ++number_index) {
        dot_product += result[number_index];
    }

    for (size_t number_index{last_vector_index}; number_index < array_size;
         ++number_index) {
        dot_product += first_array[number_index] * second_array[number_index];
    }

    return dot_product;
}

float calculate_dot_product_loop(const float *first_array,
                                 const float *second_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr) {
        return 0.0f;
    }

    float dot_product{0.0f};

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        dot_product += first_array[number_index] * second_array[number_index];
    }

    return dot_product;
}

void fill_array(float *array, size_t array_size) {
    if (array == nullptr) {
        return;
    }

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        array[number_index] = static_cast<float>(rand()) / RAND_MAX;
    }
}

bool verify_arrays_equal(const float *first_array, const float *second_array,
                         size_t array_size) {
    if (first_array == nullptr || second_array == nullptr) {
        return false;
    }

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        if (first_array[number_index] != second_array[number_index]) {
            std::cout << "Mismatch at index " << number_index
                      << ": first value = " << first_array[number_index]
                      << ", second value = " << second_array[number_index]
                      << "\n";
            return false;
        }
    }

    return true;
}

template <typename Func>
void measure_time(Func function, const std::string &name) {
    auto start{std::chrono::high_resolution_clock::now()};
    function();
    auto end{std::chrono::high_resolution_clock::now()};

    std::chrono::duration<double> elapsed{end - start};
    std::cout << name << " time: " << elapsed.count() << " seconds\n";
}

int main() {
    std::srand(std::time(nullptr));

    const size_t array_size{4096};
    const size_t size{array_size * sizeof(float)};

    // Allocate input and output arrays
    auto free_deleter = [](void *pointer) { free(pointer); };
    using array_unique_ptr = std::unique_ptr<float, decltype(free_deleter)>;

    const array_unique_ptr first_array{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const array_unique_ptr second_array{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const array_unique_ptr result_array_simd{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const array_unique_ptr result_array_loop{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};

    // Initialize input arrays
    fill_array(first_array.get(), array_size);
    fill_array(second_array.get(), array_size);

    // Perform SIMD-based vector addition
    measure_time(
        [&]() {
            add_vectors_simd(first_array.get(), second_array.get(),
                             result_array_simd.get(), array_size);
        },
        "SIMD vector addition");

    // Perform loop-based vector addition for validation
    measure_time(
        [&]() {
            add_vectors_loop(first_array.get(), second_array.get(),
                             result_array_loop.get(), array_size);
        },
        "Loop vector addition");

    // Check if both results match
    verify_arrays_equal(result_array_simd.get(), result_array_loop.get(),
                        array_size);

    // Perform SIMD-based dot product
    float dot_product_simd{0.0f};
    measure_time(
        [&]() {
            dot_product_simd = calculate_dot_product_simd(
                first_array.get(), second_array.get(), array_size);
        },
        "SIMD dot product");

    // Perform loop-based dot product for validation
    float dot_product_loop{0.0f};
    measure_time(
        [&]() {
            dot_product_loop = calculate_dot_product_loop(
                first_array.get(), second_array.get(), array_size);
        },
        "Loop dot product");

    // Check if both results match
    std::cout << "SIMD dot product: " << dot_product_simd << '\n';
    std::cout << "Loop dot product: " << dot_product_loop << '\n';

    return 0;
}
