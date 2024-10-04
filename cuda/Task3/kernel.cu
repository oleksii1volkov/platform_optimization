#include <chrono>
#include <cstdlib>
#include <ctime>
#include <cuda_runtime.h>
#include <iostream>
#include <memory>

__global__ void reduceKernel(const float *inputVector, float *outputVector,
                             unsigned int vectorSize) {
    extern __shared__ float sharedData[];

    const unsigned int threadIndex{threadIdx.x};
    const unsigned int elementIndex{blockIdx.x * blockDim.x * 2 + threadIdx.x};

    // Load elements into shared memory, each thread loads two elements
    sharedData[threadIndex] =
        (elementIndex < vectorSize)
            ? inputVector[elementIndex] + inputVector[elementIndex + blockDim.x]
            : 0.0f;
    __syncthreads();

    // Perform reduction in shared memory
    for (unsigned int stride{blockDim.x / 2}; stride > 0; stride >>= 1) {
        if (threadIndex < stride) {
            sharedData[threadIndex] += sharedData[threadIndex + stride];
        }
        __syncthreads();
    }

    // Write result of this block to global memory
    if (threadIndex == 0) {
        outputVector[blockIdx.x] = sharedData[0];
    }
}

float reduceDevice(float *inputVector, unsigned int vectorSize) {
    if (inputVector == nullptr) {
        return 0.0f;
    }

    const unsigned int threadsPerBlock{512};
    unsigned int blocksPerGrid{(vectorSize + threadsPerBlock * 2 - 1) /
                               (threadsPerBlock * 2)};
    const unsigned int sharedMemorySize{threadsPerBlock * sizeof(float)};

    auto cudaDeleter = [](float *pointer) { cudaFree(pointer); };
    using device_vector_unique_ptr =
        std::unique_ptr<float, decltype(cudaDeleter)>;

    float *outputVectorRaw{nullptr};
    if (cudaSuccess !=
        cudaMalloc((void **)&outputVectorRaw, blocksPerGrid * sizeof(float))) {
        std::cerr << "Failed to allocate memory for the output vector on device"
                  << std::endl;
        return 0.0f;
    }
    const device_vector_unique_ptr outputVector{outputVectorRaw, cudaDeleter};

    while (blocksPerGrid > 1) {
        reduceKernel<<<blocksPerGrid, threadsPerBlock, sharedMemorySize>>>(
            inputVector, outputVectorRaw, vectorSize);
        cudaDeviceSynchronize();

        std::swap(inputVector, outputVectorRaw);

        vectorSize = blocksPerGrid;
        blocksPerGrid =
            (vectorSize + threadsPerBlock * 2 - 1) / (threadsPerBlock * 2);
    }

    reduceKernel<<<1, threadsPerBlock, sharedMemorySize>>>(
        inputVector, outputVectorRaw, vectorSize);
    cudaDeviceSynchronize();

    float sum{0};

    if (cudaSuccess != cudaMemcpy(&sum, outputVectorRaw, sizeof(float),
                                  cudaMemcpyDeviceToHost)) {
        std::cerr << "Failed to copy output vector from device to host"
                  << std::endl;
        return 0.0f;
    }

    return sum;
}

float reduceHost(const float *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return 0.0f;
    }

    float sum{0};

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        sum += vector[elementIndex];
    }

    return sum;
}

void fillVectorWithRandomNumbers(float *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return;
    }

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        vector[elementIndex] = static_cast<float>(rand()) / RAND_MAX;
    }
}

int main() {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    using host_vector_unique_ptr = std::unique_ptr<float[]>;

    const unsigned int vectorSize{1 << 24};
    const host_vector_unique_ptr hostInputVector{new float[vectorSize]};

    fillVectorWithRandomNumbers(hostInputVector.get(), vectorSize);

    auto cudaDeleter = [](float *pointer) { cudaFree(pointer); };
    using device_vector_unique_ptr =
        std::unique_ptr<float, decltype(cudaDeleter)>;

    const size_t vectorMemorySize{vectorSize * sizeof(float)};

    float *deviceInputVectorRaw{nullptr};
    if (cudaSuccess !=
        cudaMalloc((void **)&deviceInputVectorRaw, vectorMemorySize)) {
        std::cerr << "Failed to allocate memory for the input vector on device"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const device_vector_unique_ptr deviceInputVector{deviceInputVectorRaw,
                                                     cudaDeleter};

    if (cudaSuccess != cudaMemcpy(deviceInputVector.get(),
                                  hostInputVector.get(), vectorMemorySize,
                                  cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy input vector from host to device"
                  << std::endl;
        return EXIT_FAILURE;
    }

    // Warm up
    reduceDevice(deviceInputVector.get(), vectorSize);

    if (cudaSuccess != cudaMemcpy(deviceInputVector.get(),
                                  hostInputVector.get(), vectorMemorySize,
                                  cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy input vector from host to device"
                  << std::endl;
        return EXIT_FAILURE;
    }

    const auto deviceStart{std::chrono::high_resolution_clock::now()};
    const auto deviceSum{reduceDevice(deviceInputVector.get(), vectorSize)};
    const auto deviceEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double> deviceDuration{deviceEnd - deviceStart};

    std::cout << "GPU Sum: " << deviceSum << "\n";
    std::cout << "GPU reduction time: " << deviceDuration.count()
              << " seconds\n";

    const auto hostStart{std::chrono::high_resolution_clock::now()};
    const auto hostSum{reduceHost(hostInputVector.get(), vectorSize)};
    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double> hostDuration{hostEnd - hostStart};

    std::cout << "CPU Sum: " << hostSum << "\n";
    std::cout << "CPU reduction time: " << hostDuration.count() << " seconds\n";

    return EXIT_SUCCESS;
}
