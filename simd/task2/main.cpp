#include <chrono>
#include <cstdlib>
#include <ctime>
#include <immintrin.h>
#include <iostream>
#include <memory>

void *aligned_malloc(size_t size) {
    void *pointer{nullptr};
    posix_memalign(&pointer, 32, size);

    return pointer;
}

void add_array_simd_aligned(const int *array, int *result_array,
                            size_t array_size) {
    if (array == nullptr || result_array == nullptr) {
        return;
    }

    const size_t simd_width{8};
    size_t last_vector_index{array_size - (array_size % simd_width)};

    for (size_t vector_index{0}; vector_index < last_vector_index;
         vector_index += simd_width) {
        __m256i vector{_mm256_load_si256((__m256i *)&array[vector_index])};
        __m256i result_vector{_mm256_add_epi32(vector, vector)};
        _mm256_store_si256((__m256i *)&result_array[vector_index],
                           result_vector);
    }

    for (size_t number_index{last_vector_index}; number_index < array_size;
         ++number_index) {
        result_array[number_index] = array[number_index] + array[number_index];
    }
}

void add_array_simd(const int *array, int *result_array, size_t array_size) {
    if (array == nullptr || result_array == nullptr) {
        return;
    }

    const size_t simd_width{8};
    size_t last_vector_index{array_size - (array_size % simd_width)};

    for (size_t vector_index{0}; vector_index < last_vector_index;
         vector_index += simd_width) {
        __m256i vector{_mm256_loadu_si256((__m256i *)&array[vector_index])};
        __m256i result_vector{_mm256_add_epi32(vector, vector)};
        _mm256_storeu_si256((__m256i *)&result_array[vector_index],
                            result_vector);
    }

    for (size_t number_index{last_vector_index}; number_index < array_size;
         ++number_index) {
        result_array[number_index] = array[number_index] + array[number_index];
    }
}

void add_array_loop(const int *array, int *result_array, size_t array_size) {
    if (array == nullptr || result_array == nullptr) {
        return;
    }

    for (size_t number_index = 0; number_index < array_size; ++number_index) {
        result_array[number_index] = array[number_index] + array[number_index];
    }
}

void fill_array(int *array, size_t array_size) {
    if (array == nullptr) {
        return;
    }

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        array[number_index] = std::rand();
    }
}

template <typename Func>
void measure_time(Func function, const std::string &name) {
    auto start{std::chrono::high_resolution_clock::now()};
    function();
    auto end{std::chrono::high_resolution_clock::now()};

    std::chrono::duration<double> elapsed = end - start;
    std::cout << name << " time: " << elapsed.count() << " seconds\n";
}

bool verify_arrays_equal(const int *first_array, const int *second_array,
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

int main() {
    std::srand(std::time(nullptr));

    const size_t array_size{4096};

    // Allocate memory for input and result arrays
    const std::unique_ptr<int[]> array{new int[array_size]};
    const std::unique_ptr<int[]> result_array_simd{new int[array_size]};
    const std::unique_ptr<int[]> result_array_loop{new int[array_size]};

    // Initialize input array with values
    fill_array(array.get(), array_size);

    // Measure and compare the execution time of SIMD and loop-based addition
    measure_time(
        [&]() {
            add_array_simd(array.get(), result_array_simd.get(), array_size);
        },
        "SIMD addition");
    measure_time(
        [&]() {
            add_array_loop(array.get(), result_array_loop.get(), array_size);
        },
        "Loop addition");

    // Verify that the results are the same
    verify_arrays_equal(result_array_simd.get(), result_array_loop.get(),
                        array_size);

    // Allocate aligned memory for input and result arrays
    auto free_deleter = [](int *pointer) { std::free(pointer); };
    using array_unique_ptr = std::unique_ptr<int, decltype(free_deleter)>;

    const array_unique_ptr aligned_array{
        reinterpret_cast<int *>(aligned_malloc(array_size * sizeof(int))),
        free_deleter};
    const array_unique_ptr result_aligned_array_simd{
        reinterpret_cast<int *>(aligned_malloc(array_size * sizeof(int))),
        free_deleter};
    const array_unique_ptr result_aligned_array_loop{
        reinterpret_cast<int *>(aligned_malloc(array_size * sizeof(int))),
        free_deleter};

    // Initialize input array with values
    fill_array(aligned_array.get(), array_size);

    // Measure and compare the execution time of SIMD and loop-based addition
    measure_time(
        [&]() {
            add_array_simd_aligned(aligned_array.get(),
                                   result_aligned_array_simd.get(), array_size);
        },
        "SIMD addition aligned");
    measure_time(
        [&]() {
            add_array_loop(aligned_array.get(), result_aligned_array_loop.get(),
                           array_size);
        },
        "Loop addition aligned");

    // Verify that the results are the same
    verify_arrays_equal(result_aligned_array_simd.get(),
                        result_aligned_array_loop.get(), array_size);

    return 0;
}
