#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <immintrin.h>
#include <iostream>
#include <memory>
#include <string_view>

void *aligned_malloc(size_t size) {
    void *pointer{nullptr};
    posix_memalign(&pointer, 32, size);

    return pointer;
}

size_t count_substring_simd(const char *string, const char *substring) {
    if (string == nullptr || substring == nullptr) {
        return 0;
    }

    const size_t string_length{strlen(string)};
    const size_t substring_length{strlen(substring)};

    if (substring_length > string_length) {
        return 0;
    }

    const size_t simd_width{32};
    size_t substring_count{0};

    for (size_t string_char_index{0};
         string_char_index <= string_length - substring_length;
         ++string_char_index) {
        bool match_found{true};

        // Compare substring in 32-byte chunks
        for (size_t substring_char_index{0};
             substring_char_index < substring_length;
             substring_char_index += simd_width) {
            // Calculate the chunk size to handle the last chunk correctly
            const size_t substring_chunk_size{
                (substring_char_index + simd_width <= substring_length)
                    ? (simd_width)
                    : (substring_length - substring_char_index)};

            if (substring_chunk_size < simd_width) {
                // For small/partial chunks, use a manual byte-wise comparison
                if (memcmp(&string[string_char_index + substring_char_index],
                           &substring[substring_char_index],
                           substring_chunk_size) != 0) {
                    match_found = false;
                    break;
                }
            } else {
                // Load the substring chunk into a SIMD register
                __m256i substring_chunk{_mm256_load_si256(
                    (__m256i *)&substring[substring_char_index])};

                // Load the string chunk into a SIMD register (unaligned load)
                __m256i string_chunk{_mm256_loadu_si256(
                    (__m256i
                         *)&string[string_char_index + substring_char_index])};

                // Compare the 32-byte chunks
                __m256i result{
                    _mm256_cmpeq_epi8(string_chunk, substring_chunk)};

                // Extract comparison result as a mask
                int mask{_mm256_movemask_epi8(result)};

                // All 32 bytes must match
                if (mask != -1) { // -1 means all 32 bits in the mask are 1
                    match_found = false;
                    break;
                }
            }
        }

        // If all chunks matched, count this as a valid occurrence
        if (match_found) {
            ++substring_count;
        }
    }

    return substring_count;
}

size_t count_substring_loop(const char *string, const char *substring) {
    if (string == nullptr || substring == nullptr) {
        return 0;
    }

    std::string_view string_view{string};
    std::string_view substring_view{substring};
    size_t substring_count{0};
    size_t char_index{0};

    while (char_index <= string_view.length() - substring_view.length()) {
        const auto substring_position =
            string_view.find(substring_view, char_index);

        if (substring_position != std::string::npos) {
            ++substring_count;
            char_index = substring_position + 1;
        } else {
            break;
        }
    }

    return substring_count;
}

void generate_random_string(char *string, size_t string_size) {
    if (string == nullptr || string_size == 0) {
        return;
    }

    const char charset[]{"abcdefghijklmnopqrstuvwxyz"};
    const size_t charset_size{sizeof(charset) - 1};

    for (size_t char_index{0}; char_index < string_size - 1; ++char_index) {
        string[char_index] = charset[std::rand() % charset_size];
    }

    string[string_size - 1] = '\0';
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

    auto free_deleter = [](void *pointer) { free(pointer); };
    using string_unique_ptr = std::unique_ptr<char, decltype(free_deleter)>;

    // Allocate input and output arrays
    const size_t string_size{1024 * 1024 + 1};
    const size_t substring_size{32 + 1};

    const string_unique_ptr string{
        reinterpret_cast<char *>(aligned_malloc(string_size)), free_deleter};
    const string_unique_ptr substring{
        reinterpret_cast<char *>(aligned_malloc(substring_size)), free_deleter};

    // Generate random strings
    generate_random_string(string.get(), string_size);
    generate_random_string(substring.get(), substring_size);

    // auto null_deleter = [](const void *pointer) {};
    // using string_unique_ptr =
    //     std::unique_ptr<const char, decltype(null_deleter)>;

    // const string_unique_ptr string{"aaaaaa", null_deleter};
    // const string_unique_ptr substring{"aa", null_deleter};

    // Count occurrences
    size_t substring_count_loop{0};
    measure_time(
        [&]() {
            substring_count_loop =
                count_substring_loop(string.get(), substring.get());
        },
        "Loop-based substring count");

    size_t substring_count_simd{0};
    measure_time(
        [&]() {
            substring_count_simd =
                count_substring_simd(string.get(), substring.get());
        },
        "SIMD substring count");

    std::cout << "Occurrences of substring(Loop): " << substring_count_loop
              << std::endl;
    std::cout << "Occurrences of substring(SIMD): " << substring_count_simd
              << std::endl;

    return 0;
}
