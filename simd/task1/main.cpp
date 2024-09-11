#include <chrono>
#include <cstdlib>
#include <ctime>
#include <immintrin.h>
#include <iostream>
#include <vector>

void add_arrays_simd(const int *first_array, const int *second_array,
                     int *result_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr ||
        result_array == nullptr) {
        return;
    }

    const size_t simd_width{8};
    size_t last_vector_index{array_size - (array_size % simd_width)};

    for (size_t vector_index{0}; vector_index < last_vector_index;
         vector_index += simd_width) {
        __m256i first_vector{
            _mm256_loadu_si256((__m256i *)&first_array[vector_index])};
        __m256i second_vector{
            _mm256_loadu_si256((__m256i *)&second_array[vector_index])};
        __m256i result_vector{_mm256_add_epi32(first_vector, second_vector)};
        _mm256_storeu_si256((__m256i *)&result_array[vector_index],
                            result_vector);
    }

    for (size_t number_index{last_vector_index}; number_index < array_size;
         ++number_index) {
        result_array[number_index] =
            first_array[number_index] + second_array[number_index];
    }
}

void add_arrays_loop(const int *first_array, const int *second_array,
                     int *result_array, size_t array_size) {
    if (first_array == nullptr || second_array == nullptr ||
        result_array == nullptr) {
        return;
    }

    for (size_t number_index{0}; number_index < array_size; ++number_index) {
        result_array[number_index] =
            first_array[number_index] + second_array[number_index];
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

    // Initialize arrays
    std::vector<int> first_array(array_size, 0);
    std::vector<int> second_array(array_size, 0);
    std::vector<int> result_array_simd(array_size, 0);
    std::vector<int> result_array_loop(array_size, 0);

    // Populate the arrays with values
    fill_array(first_array.data(), array_size);
    fill_array(second_array.data(), array_size);

    // Loop-based addition and performance measurement
    measure_time(
        [&]() {
            add_arrays_loop(first_array.data(), second_array.data(),
                            result_array_loop.data(), array_size);
        },
        "Loop-based addition");

    // SIMD addition and performance measurement
    measure_time(
        [&]() {
            add_arrays_simd(first_array.data(), second_array.data(),
                            result_array_simd.data(), array_size);
        },
        "SIMD addition");

    // Verify results
    verify_arrays_equal(result_array_simd.data(), result_array_loop.data(),
                        array_size);

    return 0;
}
