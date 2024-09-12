#include <chrono>
#include <cmath>
#include <cstdlib>
#include <immintrin.h>
#include <iomanip>
#include <iostream>
#include <memory>

void *aligned_malloc(size_t size) {
    void *pointer{nullptr};
    posix_memalign(&pointer, 32, size);

    return pointer;
}

void print_matrix(const float *matrix, size_t matrix_size) {
    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size; ++column_index)
            std::cout << std::setw(10)
                      << matrix[row_index * matrix_size + column_index] << " ";
    }

    std::cout << "\n";
}

void transpose_matrix(const float *source_matrix, float *destination_matrix,
                      size_t matrix_size) {
    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size;
             ++column_index) {
            destination_matrix[column_index * matrix_size + row_index] =
                source_matrix[row_index * matrix_size + column_index];
        }
    }
}

float simd_horizontal_sum(__m256 vector) {
    __m128 high{_mm256_extractf128_ps(vector, 1)}; // Extract the high 128 bits
    __m128 low{_mm256_castps256_ps128(vector)};    // Get the low 128 bits
    __m128 sum{_mm_add_ps(low, high)};             // Add high and low parts

    sum = _mm_hadd_ps(sum, sum); // Horizontal add
    sum = _mm_hadd_ps(sum, sum); // Horizontal add again

    return _mm_cvtss_f32(sum); // Return the final sum
}

void multiply_matrices_transposed_simd(const float *first_matrix,
                                       const float *second_matrix_transposed,
                                       float *result_matrix,
                                       size_t matrix_size) {
    if (first_matrix == nullptr || second_matrix_transposed == nullptr ||
        result_matrix == nullptr) {
        return;
    }

    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size;
             ++column_index) {
            __m256 result_vector{
                _mm256_setzero_ps()}; // Initialize the accumulator to zero

            for (size_t element_index{0}; element_index < matrix_size;
                 element_index += 8) {
                // Load 8 elements from row row_index of first_matrix
                __m256 first_vector{_mm256_load_ps(
                    &first_matrix[row_index * matrix_size + element_index])};

                // Load 8 elements from column column_index of second_matrix
                // (which is a row of second_matrix_transposed)
                __m256 second_vector{_mm256_load_ps(
                    &second_matrix_transposed[column_index * matrix_size +
                                              element_index])};

                // Perform element-wise multiplication and accumulate
                result_vector =
                    _mm256_fmadd_ps(first_vector, second_vector, result_vector);
            }

            // Horizontal sum of the SIMD vector to get a single result
            result_matrix[row_index * matrix_size + column_index] =
                simd_horizontal_sum(result_vector);
        }
    }
}

void multiply_matrices_simd(const float *first_matrix,
                            const float *second_matrix, float *result_matrix,
                            size_t matrix_size) {
    if (first_matrix == nullptr || second_matrix == nullptr ||
        result_matrix == nullptr) {
        return;
    }

    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size;
             ++column_index) {
            __m256 result_vector{
                _mm256_setzero_ps()}; // Initialize the accumulator to zero

            for (size_t element_index{0}; element_index < matrix_size;
                 element_index += 8) {
                // Load 8 elements from row row_index of first_matrix
                __m256 first_vector{_mm256_load_ps(
                    &first_matrix[row_index * matrix_size + element_index])};

                // Load 8 elements from column j of B manually using
                // _mm256_set_ps
                __m256 second_vector{_mm256_set_ps(
                    second_matrix[(element_index + 7) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 6) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 5) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 4) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 3) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 2) * matrix_size +
                                  column_index],
                    second_matrix[(element_index + 1) * matrix_size +
                                  column_index],
                    second_matrix[element_index * matrix_size + column_index])};

                // Perform element-wise multiplication and accumulate
                result_vector =
                    _mm256_fmadd_ps(first_vector, second_vector, result_vector);
            }

            // Horizontal sum of the SIMD vector to get a single result
            result_matrix[row_index * matrix_size + column_index] =
                simd_horizontal_sum(result_vector);
        }
    }
}

void multiply_matrices_loop(const float *first_matrix,
                            const float *second_matrix, float *result_matrix,
                            int matrix_size) {
    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size;
             ++column_index) {
            float sum = 0.0f;

            for (size_t element_index{0}; element_index < matrix_size;
                 ++element_index) {
                sum +=
                    first_matrix[row_index * matrix_size + element_index] *
                    second_matrix[element_index * matrix_size + column_index];
            }

            result_matrix[row_index * matrix_size + column_index] = sum;
        }
    }
}

void fill_matrix(float *matrix, size_t matrix_size) {
    if (matrix == nullptr) {
        return;
    }

    for (size_t element_index{0}; element_index < matrix_size * matrix_size;
         ++element_index) {
        matrix[element_index] = static_cast<float>(std::rand()) / RAND_MAX;
    }
}

bool verify_matrices_equal(const float *first_matrix,
                           const float *second_matrix, size_t matrix_size) {
    if (first_matrix == nullptr || second_matrix == nullptr) {
        return false;
    }

    for (size_t row_index{0}; row_index < matrix_size; ++row_index) {
        for (size_t column_index{0}; column_index < matrix_size;
             ++column_index) {
            const auto &first_value{
                first_matrix[row_index * matrix_size + column_index]};
            const auto &second_value{
                second_matrix[row_index * matrix_size + column_index]};

            const auto tolerance{(first_value + second_value) / 2 * 0.0001f};
            const auto difference{std::fabs(first_value - second_value)};

            if (difference > tolerance) {
                std::cout << "Mismatch at index (" << row_index << ", "
                          << column_index << "): first value = " << first_value
                          << ", second value = " << second_value
                          << ", difference = " << first_value - second_value
                          << "\n";

                return false;
            }
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

    const size_t matrix_size{512}; // Should be multiple of 8
    const size_t size{matrix_size * matrix_size * sizeof(float)};

    // Allocate and initialize matrices
    auto free_deleter = [](void *pointer) { free(pointer); };
    using matrix_unique_ptr = std::unique_ptr<float, decltype(free_deleter)>;

    const matrix_unique_ptr first_matrix{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const matrix_unique_ptr second_matrix{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const matrix_unique_ptr second_matrix_transposed{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const matrix_unique_ptr result_matrix_simd{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const matrix_unique_ptr result_matrix_transposed_simd{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};
    const matrix_unique_ptr result_matrix_loop{
        reinterpret_cast<float *>(aligned_malloc(size)), free_deleter};

    // Initialize matrices with some values
    fill_matrix(first_matrix.get(), matrix_size);
    fill_matrix(second_matrix.get(), matrix_size);

    // Measure time for loop matrix multiplication
    measure_time(
        [&]() {
            multiply_matrices_loop(first_matrix.get(), second_matrix.get(),
                                   result_matrix_loop.get(), matrix_size);
        },
        "Loop matrix multiplication");

    // Measure time for AVX matrix multiplication
    measure_time(
        [&]() {
            multiply_matrices_simd(first_matrix.get(), second_matrix.get(),
                                   result_matrix_simd.get(), matrix_size);
        },
        "SIMD matrix multiplication");

    verify_matrices_equal(result_matrix_loop.get(), result_matrix_simd.get(),
                          matrix_size);

    // Measure time for AVX matrix multiplication with transposed matrix
    measure_time(
        [&]() {
            transpose_matrix(second_matrix.get(),
                             second_matrix_transposed.get(), matrix_size);
            multiply_matrices_transposed_simd(
                first_matrix.get(), second_matrix_transposed.get(),
                result_matrix_transposed_simd.get(), matrix_size);
        },
        "SIMD matrix multiplication with transposed matrix");

    verify_matrices_equal(result_matrix_loop.get(),
                          result_matrix_transposed_simd.get(), matrix_size);

    return 0;
}
