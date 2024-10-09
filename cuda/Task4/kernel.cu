#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <thrust/device_vector.h>
#include <thrust/sort.h>
#include <vector>

void fillWithRandomNumbers(std::vector<int> &vector, size_t vectorSize) {
    for (size_t numberIndex{0}; numberIndex < vectorSize; ++numberIndex) {
        vector[numberIndex] = std::rand();
    }
}

int main() {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    const size_t vectorSize{1 << 24};
    std::vector<int> hostVector(vectorSize);
    fillWithRandomNumbers(hostVector, vectorSize);

    std::vector<int> hostVectorCopy{hostVector};

    const auto startCPU{std::chrono::high_resolution_clock::now()};
    std::sort(hostVector.begin(), hostVector.end());
    auto endCPU = std::chrono::high_resolution_clock::now();

    std::chrono::duration<double> durationCPU{endCPU - startCPU};
    std::cout << "CPU sorting time: " << durationCPU.count() << " seconds"
              << std::endl;

    thrust::device_vector<int> deviceVector{hostVectorCopy};
    thrust::device_vector<int> deviceVectorCopy{hostVectorCopy};

    // Warm up
    thrust::sort(deviceVectorCopy.begin(), deviceVectorCopy.end());

    auto startGPU{std::chrono::high_resolution_clock::now()};
    thrust::sort(deviceVector.begin(), deviceVector.end());
    auto endGPU{std::chrono::high_resolution_clock::now()};

    std::chrono::duration<double> durationGPU{endGPU - startGPU};
    std::cout << "GPU sorting time: " << durationGPU.count() << " seconds"
              << std::endl;

    thrust::copy(deviceVector.begin(), deviceVector.end(),
                 hostVectorCopy.begin());

    if (std::equal(hostVector.begin(), hostVector.end(),
                   hostVectorCopy.begin())) {
        std::cout << "Sorting is correct!" << std::endl;
    } else {
        std::cout << "Sorting results differ!" << std::endl;
    }

    return 0;
}
