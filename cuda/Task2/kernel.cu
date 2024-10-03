#include <chrono>
#include <cstdlib>
#include <ctime>
#include <cuda_runtime.h>
#include <iostream>
#include <memory>

constexpr unsigned int TILE_SIZE{16}; // Tile size for shared memory

__global__ void matrixMultiplyKernel(const float *matrixA, const float *matrixB,
                                     float *matrixC, unsigned int matrixSize) {
    __shared__ float tileA[TILE_SIZE][TILE_SIZE];
    __shared__ float tileB[TILE_SIZE][TILE_SIZE];

    const unsigned int rowIndex{blockIdx.y * TILE_SIZE + threadIdx.y};
    const unsigned int columnIndex{blockIdx.x * TILE_SIZE + threadIdx.x};
    const unsigned int tilesNumber{(matrixSize + TILE_SIZE - 1) / TILE_SIZE};

    float sum{0};

    // Loop over the tiles of the input matrices
    for (unsigned int tileIndex{0}; tileIndex < tilesNumber; ++tileIndex) {
        // Load the tiles into shared memory
        tileA[threadIdx.y][threadIdx.x] =
            matrixA[rowIndex * matrixSize + tileIndex * TILE_SIZE +
                    threadIdx.x];
        tileB[threadIdx.y][threadIdx.x] =
            matrixB[(tileIndex * TILE_SIZE + threadIdx.y) * matrixSize +
                    columnIndex];
        __syncthreads();

        // Perform multiplication for the tiles
        for (unsigned int elementIndex{0}; elementIndex < TILE_SIZE;
             ++elementIndex) {
            sum += tileA[threadIdx.y][elementIndex] *
                   tileB[elementIndex][threadIdx.x];
        }
        __syncthreads();
    }

    // Store the result in matrix C
    if (rowIndex < matrixSize && columnIndex < matrixSize) {
        matrixC[rowIndex * matrixSize + columnIndex] = sum;
    }
}

void matrixMultiplyHost(const float *matrixA, const float *matrixB,
                        float *matrixC, unsigned int matrixSize) {
    if (matrixA == nullptr || matrixB == nullptr || matrixC == nullptr) {
        return;
    }

    for (unsigned int rowIndex{0}; rowIndex < matrixSize; ++rowIndex) {
        for (unsigned int columnIndex{0}; columnIndex < matrixSize;
             ++columnIndex) {
            float sum{0};

            for (unsigned int elementIndex{0}; elementIndex < matrixSize;
                 ++elementIndex) {
                sum += matrixA[rowIndex * matrixSize + elementIndex] *
                       matrixB[elementIndex * matrixSize + columnIndex];
            }

            matrixC[rowIndex * matrixSize + columnIndex] = sum;
        }
    }
}

void matrixMultiplyDevice(const float *matrixA, const float *matrixB,
                          float *matrixC, unsigned int matrixSize) {
    if (matrixA == nullptr || matrixB == nullptr || matrixC == nullptr) {
        return;
    }

    const dim3 threadsPerBlock(TILE_SIZE, TILE_SIZE);
    const dim3 blocksPerGrid((matrixSize + TILE_SIZE - 1) / TILE_SIZE,
                             (matrixSize + TILE_SIZE - 1) / TILE_SIZE);

    matrixMultiplyKernel<<<blocksPerGrid, threadsPerBlock>>>(
        matrixA, matrixB, matrixC, matrixSize);

    cudaDeviceSynchronize();
}

void fillMatrixWithRandomNumbers(float *matrix, unsigned int matrixSize) {
    if (matrix == nullptr) {
        return;
    }

    for (unsigned int rowIndex{0}; rowIndex < matrixSize; ++rowIndex) {
        for (unsigned int columnIndex{0}; columnIndex < matrixSize;
             ++columnIndex) {
            matrix[rowIndex * matrixSize + columnIndex] =
                static_cast<float>(std::rand()) / RAND_MAX;
        }
    }
}

int main() {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    using host_matrix_unique_ptr = std::unique_ptr<float[]>;

    const unsigned int matrixSize{1024}; // Size of the matrices (N x N)

    const host_matrix_unique_ptr hostMatrixA{
        new float[matrixSize * matrixSize]};
    const host_matrix_unique_ptr hostMatrixB{
        new float[matrixSize * matrixSize]};
    const host_matrix_unique_ptr hostMatrixC{
        new float[matrixSize * matrixSize]};
    const host_matrix_unique_ptr hostMatrixCDevice{
        new float[matrixSize * matrixSize]};

    fillMatrixWithRandomNumbers(hostMatrixA.get(), matrixSize);
    fillMatrixWithRandomNumbers(hostMatrixB.get(), matrixSize);

    auto deviceDeleter = [](float *pointer) { cudaFree(pointer); };
    using device_matrix_unique_ptr =
        std::unique_ptr<float[], decltype(deviceDeleter)>;

    const size_t matrixMemorySize{matrixSize * matrixSize * sizeof(float)};

    float *deviceMatrixARaw{nullptr};
    if (cudaSuccess !=
        cudaMalloc((void **)&deviceMatrixARaw, matrixMemorySize)) {
        std::cerr << "Failed to allocate memory on the device for matrix A"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const device_matrix_unique_ptr deviceMatrixA{deviceMatrixARaw,
                                                 deviceDeleter};

    float *deviceMatrixBRaw{nullptr};
    if (cudaSuccess !=
        cudaMalloc((void **)&deviceMatrixBRaw, matrixMemorySize)) {
        std::cerr << "Failed to allocate memory on the device for matrix B"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const device_matrix_unique_ptr deviceMatrixB{deviceMatrixBRaw,
                                                 deviceDeleter};

    float *deviceMatrixCRaw{nullptr};
    if (cudaSuccess !=
        cudaMalloc((void **)&deviceMatrixCRaw, matrixMemorySize)) {
        std::cerr << "Failed to allocate memory on the device for matrix C"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const device_matrix_unique_ptr deviceMatrixC{deviceMatrixCRaw,
                                                 deviceDeleter};

    if (cudaSuccess != cudaMemcpy(deviceMatrixA.get(), hostMatrixA.get(),
                                  matrixMemorySize, cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy matrix A from host to device" << std::endl;
        return EXIT_FAILURE;
    }

    if (cudaSuccess != cudaMemcpy(deviceMatrixB.get(), hostMatrixB.get(),
                                  matrixMemorySize, cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy matrix B from host to device" << std::endl;
        return EXIT_FAILURE;
    }

    // Warm up
    matrixMultiplyDevice(deviceMatrixA.get(), deviceMatrixB.get(),
                         deviceMatrixC.get(), matrixSize);

    const auto deviceStart{std::chrono::high_resolution_clock::now()};
    matrixMultiplyDevice(deviceMatrixA.get(), deviceMatrixB.get(),
                         deviceMatrixC.get(), matrixSize);
    const auto deviceEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double> deviceDuration{deviceEnd - deviceStart};

    std::cout << "GPU matrix multiplication time: " << deviceDuration.count()
              << " seconds\n";

    const auto hostStart{std::chrono::high_resolution_clock::now()};
    matrixMultiplyHost(hostMatrixA.get(), hostMatrixB.get(), hostMatrixC.get(),
                       matrixSize);
    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double> hostDuration{hostEnd - hostStart};

    std::cout << "CPU matrix multiplication time: " << hostDuration.count()
              << " seconds\n";

    if (cudaSuccess != cudaMemcpy(hostMatrixCDevice.get(), deviceMatrixC.get(),
                                  matrixMemorySize, cudaMemcpyDeviceToHost)) {
        std::cerr << "Failed to copy matrix C from device to host" << std::endl;
        return EXIT_FAILURE;
    }

    bool match{true};
    const double tolerance{1e-4};

    for (size_t elementIndex{0}; elementIndex < matrixSize * matrixSize;
         ++elementIndex) {
        if (std::fabs(hostMatrixC[elementIndex] -
                      hostMatrixCDevice[elementIndex]) > tolerance) {
            std::cerr << "Mismatch at element " << elementIndex << "\n"
                      << "First value: " << hostMatrixC[elementIndex] << "\n"
                      << "Second value: " << hostMatrixCDevice[elementIndex]
                      << "\n";
            match = false;
            break;
        }
    }

    if (match) {
        std::cout << "Matrices match!\n";
    } else {
        std::cout << "Matrices do not match!\n";
    }

    return EXIT_SUCCESS;
}
