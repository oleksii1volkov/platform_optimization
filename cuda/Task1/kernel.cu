#include <chrono>
#include <cstdlib>
#include <ctime>
#include <cuda_runtime.h>
#include <iostream>
#include <memory>

__global__ void vectorAddKernel(const float *vectorA, const float *vectorB,
                                float *vectorC, unsigned int vectorSize) {
    const unsigned int elementIndex{blockIdx.x * blockDim.x + threadIdx.x};

    if (elementIndex < vectorSize) {
        vectorC[elementIndex] = vectorA[elementIndex] + vectorB[elementIndex];
    }
}

void vectorAddHost(const float *vectorA, const float *vectorB, float *vectorC,
                   unsigned int vectorSize) {
    if (vectorA == nullptr || vectorB == nullptr || vectorC == nullptr) {
        return;
    }

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        vectorC[elementIndex] = vectorA[elementIndex] + vectorB[elementIndex];
    }
}

void vectorAddDevice(const float *vectorA, const float *vectorB, float *vectorC,
                     unsigned int vectorSize) {
    if (vectorA == nullptr || vectorB == nullptr || vectorC == nullptr) {
        return;
    }

    const unsigned int threadsPerBlock{256};
    const unsigned int blocksPerGrid{(vectorSize + threadsPerBlock - 1) /
                                     threadsPerBlock};

    vectorAddKernel<<<blocksPerGrid, threadsPerBlock>>>(vectorA, vectorB,
                                                        vectorC, vectorSize);

    cudaDeviceSynchronize();
}

void fillWithRandomNumbers(float *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return;
    }

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        vector[elementIndex] = static_cast<float>(std::rand()) / RAND_MAX;
    }
}

int main() {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    const unsigned int vectorSize{1 << 24};

    const std::unique_ptr<float[]> hostVectorA{new float[vectorSize]};
    const std::unique_ptr<float[]> hostVectorB{new float[vectorSize]};
    const std::unique_ptr<float[]> hostVectorC{new float[vectorSize]};
    const std::unique_ptr<float[]> hostVectorCDevice{new float[vectorSize]};

    fillWithRandomNumbers(hostVectorA.get(), vectorSize);
    fillWithRandomNumbers(hostVectorB.get(), vectorSize);

    const size_t elementsSize{vectorSize * sizeof(float)};
    auto cudaDeleter = [](void *pointer) { cudaFree(pointer); };
    using cuda_vector_unique_ptr =
        std::unique_ptr<float, decltype(cudaDeleter)>;

    float *deviceVectorARaw{nullptr};
    if (cudaSuccess != cudaMalloc((void **)&deviceVectorARaw, elementsSize)) {
        std::cerr << "Failed to allocate device memory for vector A"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const cuda_vector_unique_ptr deviceVectorA{deviceVectorARaw, cudaDeleter};

    float *deviceVectorBRaw{nullptr};
    if (cudaSuccess != cudaMalloc((void **)&deviceVectorBRaw, elementsSize)) {
        std::cerr << "Failed to allocate device memory for vector B"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const cuda_vector_unique_ptr deviceVectorB{deviceVectorBRaw, cudaDeleter};

    float *deviceVectorCRaw{nullptr};
    if (cudaSuccess != cudaMalloc((void **)&deviceVectorCRaw, elementsSize)) {
        std::cerr << "Failed to allocate device memory for vector C"
                  << std::endl;
        return EXIT_FAILURE;
    }
    const cuda_vector_unique_ptr deviceVectorC{deviceVectorCRaw, cudaDeleter};

    if (cudaSuccess != cudaMemcpy(deviceVectorA.get(), hostVectorA.get(),
                                  elementsSize, cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy vector A to device" << std::endl;
        return EXIT_FAILURE;
    }

    if (cudaSuccess != cudaMemcpy(deviceVectorB.get(), hostVectorB.get(),
                                  elementsSize, cudaMemcpyHostToDevice)) {
        std::cerr << "Failed to copy vector B to device" << std::endl;
        return EXIT_FAILURE;
    }

    // Warm up
    vectorAddDevice(deviceVectorA.get(), deviceVectorB.get(),
                    deviceVectorC.get(), vectorSize);

    const auto deviceStart{std::chrono::high_resolution_clock::now()};
    vectorAddDevice(deviceVectorA.get(), deviceVectorB.get(),
                    deviceVectorC.get(), vectorSize);
    const auto deviceEnd{std::chrono::high_resolution_clock::now()};
    std::chrono::duration<double, std::milli> deviceDuration{deviceEnd -
                                                             deviceStart};

    std::cout << "GPU vector addition time: " << deviceDuration.count() << " ms"
              << std::endl;

    if (cudaSuccess != cudaMemcpy(hostVectorCDevice.get(), deviceVectorC.get(),
                                  elementsSize, cudaMemcpyDeviceToHost)) {
        std::cerr << "Failed to copy vector C from device" << std::endl;
        return EXIT_FAILURE;
    }

    const auto hostStart{std::chrono::high_resolution_clock::now()};
    vectorAddHost(hostVectorA.get(), hostVectorB.get(), hostVectorC.get(),
                  vectorSize);
    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    std::chrono::duration<double, std::milli> hostDuration{hostEnd - hostStart};

    std::cout << "CPU vector addition time: " << hostDuration.count() << " ms"
              << std::endl;

    bool match{true};
    const double tolerance{1e-5};

    for (size_t elementIndex{0}; elementIndex < vectorSize; ++elementIndex) {
        if (std::abs(hostVectorC[elementIndex] -
                     hostVectorCDevice[elementIndex]) > tolerance) {
            match = false;
            std::cerr << "Results mismatch at index " << elementIndex << "!\n";
            break;
        }
    }

    if (match) {
        std::cout << "Device and host results match.\n";
    }

    return EXIT_SUCCESS;
}
