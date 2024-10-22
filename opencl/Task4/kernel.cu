#include <CL/cl.h>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <memory>

#ifdef _WIN32
#include <malloc.h>
#else
#include <errno.h>
#include <stdlib.h>
#endif

void *aligned_malloc(size_t size, size_t alignment) {
#ifdef _WIN32
    return _aligned_malloc(size, alignment);
#else
    void *pointer;
    if (posix_memalign(&pointer, alignment, size) != 0) {
        return NULL;
    }
    return pointer;
#endif
}

void aligned_free(void *pointer) {
#ifdef _WIN32
    _aligned_free(pointer);
#else
    free(pointer);
#endif
}

// OpenCL kernel for bitonic sort
const char *bitonicSortKernelSource{R"(
__kernel void bitonicSortKernel(__global int* vector,
                                const unsigned int comparisonDistance,
                                const unsigned int bitonicSequenceSize)
{
    const unsigned int elementIndex = get_global_id(0);
    const unsigned int partnerElementIndex = elementIndex ^ comparisonDistance;

    if (partnerElementIndex > elementIndex) {
        // Check if element belongs to the first or second half of the current bitonic sequence
        if ((elementIndex & bitonicSequenceSize) == 0) {
            // Sort in ascending order
            if (vector[elementIndex] > vector[partnerElementIndex]) {
                // Swap elements if out of order
                int temp = vector[elementIndex];
                vector[elementIndex] = vector[partnerElementIndex];
                vector[partnerElementIndex] = temp;
            }
        } else {
            // Sort in descending order
            if (vector[elementIndex] < vector[partnerElementIndex]) {
                // Swap elements if out of order
                int temp = vector[elementIndex];
                vector[elementIndex] = vector[partnerElementIndex];
                vector[partnerElementIndex] = temp;
            }
        }
    }
}
)"};

// OpenCL kernel for merge sort
const char *mergeSortKernelSource{R"(
__kernel void mergeSortKernel(__global const int* inputVector,
                              __global int* outputVector,
                              const unsigned int vectorSize,
                              const unsigned int chunkSize) {
    const unsigned int globalIndex = get_global_id(0);
    const unsigned int leftStartIndex = globalIndex * 2 * chunkSize;
    
    if (leftStartIndex >= vectorSize) {
        return;
    }

    const unsigned int rightStartIndex = leftStartIndex + chunkSize;
    const unsigned int leftEndIndex = min(rightStartIndex, vectorSize);
    const unsigned int rightEndIndex = min(rightStartIndex + chunkSize, vectorSize);
    
    unsigned int i = leftStartIndex;
    unsigned int j = rightStartIndex;
    unsigned int k = leftStartIndex;

    // Merging the two halves into the output array
    while (i < leftEndIndex && j < rightEndIndex) {
        if (inputVector[i] < inputVector[j]) {
            outputVector[k++] = inputVector[i++];
        } else {
            outputVector[k++] = inputVector[j++];
        }
    }

    // If there are remaining elements in the left half, copy them
    while (i < leftEndIndex) {
        outputVector[k++] = inputVector[i++];
    }

    // If there are remaining elements in the right half, copy them
    while (j < rightEndIndex) {
        outputVector[k++] = inputVector[j++];
    }
}
)"};

void fillVectorWithRandomNumbers(int *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return;
    }

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        vector[elementIndex] = std::rand();
    }
}

void printBuildLog(const cl_program &program, const cl_device_id &deviceId) {
    size_t logSize;
    clGetProgramBuildInfo(program, deviceId, CL_PROGRAM_BUILD_LOG, 0, nullptr,
                          &logSize);

    const auto buildLog{std::unique_ptr<char[]>(new char[logSize + 1])};
    clGetProgramBuildInfo(program, deviceId, CL_PROGRAM_BUILD_LOG, logSize,
                          buildLog.get(), nullptr);

    buildLog[logSize] = '\0';
    std::cerr << "Build log:\n" << buildLog.get() << std::endl;
}

template <typename R, typename T> class AutoReleaseObject {
public:
    AutoReleaseObject(R (*releaseFunction)(T), T &object)
        : m_releaseFunction(releaseFunction), m_object(object) {}

    AutoReleaseObject(const AutoReleaseObject &) = delete;
    AutoReleaseObject &operator=(const AutoReleaseObject &) = delete;

    AutoReleaseObject(AutoReleaseObject &&other) noexcept
        : m_releaseFunction{other.m_releaseFunction}, m_object{other.m_object} {
        other.m_releaseFunction = nullptr;
    }

    AutoReleaseObject &operator=(AutoReleaseObject &&) = delete;

    ~AutoReleaseObject() {
        if (m_releaseFunction) {
            m_releaseFunction(m_object);
        }
    }

private:
    R (*m_releaseFunction)(T);
    T &m_object;
};

template <typename T, typename R>
auto createAutoReleaseObject(R (*releaseFunction)(T), T &object) {
    return AutoReleaseObject<R, T>(releaseFunction, object);
}

#define checkError(expression, message)                                        \
    do {                                                                       \
        const cl_int error{(expression)};                                      \
        if (CL_SUCCESS != error) {                                             \
            std::cerr << "Error: " << message << " (Error Code: " << error     \
                      << ")" << std::endl;                                     \
            return EXIT_FAILURE;                                               \
        }                                                                      \
    } while (0)

cl_int getEventDuration(cl_event event, cl_ulong &eventDuration) {
    cl_ulong eventStart{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START,
                                       sizeof(cl_ulong), &eventStart, nullptr),
               "Failed to get start time");

    cl_ulong eventEnd{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END,
                                       sizeof(cl_ulong), &eventEnd, nullptr),
               "Failed to get end time");

    eventDuration = eventEnd - eventStart;

    return CL_SUCCESS;
}

int bitonicSort(cl_command_queue commandQueue, cl_kernel kernel,
                cl_mem deviceVector, unsigned int vectorSize,
                double &deviceDuration) {
    deviceDuration = 0.0;

    for (unsigned int bitonicSequenceSize{2}; bitonicSequenceSize <= vectorSize;
         bitonicSequenceSize <<= 1) {
        for (unsigned int comparisonDistance{bitonicSequenceSize >> 1};
             comparisonDistance > 0; comparisonDistance >>= 1) {
            checkError(clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceVector),
                       "Failed to set kernel argument for input vector");
            checkError(clSetKernelArg(kernel, 1, sizeof(unsigned int),
                                      &comparisonDistance),
                       "Failed to set kernel argument for comparison distance");
            checkError(
                clSetKernelArg(kernel, 2, sizeof(unsigned int),
                               &bitonicSequenceSize),
                "Failed to set kernel argument for bitonic sequence size");

            cl_event kernelExecutionEvent{};
            const auto _kernelExecutionEvent{
                createAutoReleaseObject(clReleaseEvent, kernelExecutionEvent)};

            const size_t globalWorkSize{vectorSize};
            checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 1, nullptr,
                                              &globalWorkSize, nullptr, 0,
                                              nullptr, &kernelExecutionEvent),
                       "Failed to execute OpenCL kernel");

            checkError(clFinish(commandQueue),
                       "Failed to finish OpenCL command queue");

            // Get the time spent on the device
            cl_ulong kernelDuration{};
            checkError(getEventDuration(kernelExecutionEvent, kernelDuration),
                       "Failed to get event duration");
            deviceDuration += kernelDuration;
        }
    }

    return EXIT_SUCCESS;
}

int runBitonicSort(const cl_context &context, const cl_device_id &deviceId,
                   const cl_command_queue &commandQueue, const int *vector,
                   int *vectorDevice, const unsigned int vectorSize) {
    // Create buffer for vector
    cl_int errorCode{};
    cl_mem deviceVector{};
    const auto _deviceVector{
        createAutoReleaseObject(clReleaseMemObject, deviceVector)};
    deviceVector = clCreateBuffer(
        context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
        vectorSize * sizeof(int), const_cast<int *>(vector), &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for vector");

    // Create and build program from source
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};
    program = clCreateProgramWithSource(context, 1, &bitonicSortKernelSource,
                                        nullptr, &errorCode);
    checkError(errorCode, "Failed to create OpenCL program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);
    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    // Create kernel
    cl_kernel kernel{};
    const auto _kernel{createAutoReleaseObject(clReleaseKernel, kernel)};
    kernel = clCreateKernel(program, "bitonicSortKernel", &errorCode);
    checkError(errorCode, "Failed to create OpenCL kernel");

    // Execute kernel
    double deviceDuration{0.0};
    errorCode = bitonicSort(commandQueue, kernel, deviceVector, vectorSize,
                            deviceDuration);
    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to execute bitonic sort\n";
        return EXIT_FAILURE;
    }

    std::cout << "OpenCL bitonic sort execution time: " << deviceDuration * 1e-6
              << " milliseconds\n";

    // Copy the vector from the device to the host
    checkError(clEnqueueReadBuffer(commandQueue, deviceVector, CL_TRUE, 0,
                                   vectorSize * sizeof(int), vectorDevice, 0,
                                   nullptr, nullptr),
               "Failed to copy vector from device to host");

    checkError(clFinish(commandQueue), "Failed to finish OpenCL command queue");

    return EXIT_SUCCESS;
}

int parallelMergeSort(cl_command_queue commandQueue, cl_kernel kernel,
                      cl_mem deviceInputVector, cl_mem deviceOutputVector,
                      unsigned int vectorSize, double &deviceDuration) {
    unsigned int chunkSize{1};
    deviceDuration = 0.0;

    while (chunkSize < vectorSize) {
        // Set the arguments for the merge kernel
        checkError(
            clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceInputVector),
            "Failed to set kernel argument for input vector");
        checkError(
            clSetKernelArg(kernel, 1, sizeof(cl_mem), &deviceOutputVector),
            "Failed to set kernel argument for output vector");
        checkError(clSetKernelArg(kernel, 2, sizeof(unsigned int), &vectorSize),
                   "Failed to set kernel argument for vector size");
        checkError(clSetKernelArg(kernel, 3, sizeof(unsigned int), &chunkSize),
                   "Failed to set kernel argument for chunk size");

        // Determine the number of global work items (number of pairs of chunks
        // to merge)
        size_t globalWorkSize{(vectorSize + (2 * chunkSize) - 1) /
                              (2 * chunkSize)};
        cl_event kernelExecutionEvent{};
        const auto _kernelExecutionEvent{
            createAutoReleaseObject(clReleaseEvent, kernelExecutionEvent)};

        // Execute the merge kernel
        checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 1, nullptr,
                                          &globalWorkSize, nullptr, 0, nullptr,
                                          &kernelExecutionEvent),
                   "Failed to execute merge OpenCL kernel");

        // Wait for the operations to finish before proceeding
        checkError(clFinish(commandQueue),
                   "Failed to finish OpenCL command queue");

        // Get the time spent on the device
        cl_ulong kernelDuration{};
        checkError(getEventDuration(kernelExecutionEvent, kernelDuration),
                   "Failed to get event duration");
        deviceDuration += kernelDuration;

        // Enqueue the copy operation
        checkError(clEnqueueCopyBuffer(commandQueue, deviceOutputVector,
                                       deviceInputVector, 0, 0,
                                       sizeof(int) * vectorSize, 0, NULL,
                                       &kernelExecutionEvent),
                   "Failed to copy OpenCL buffer");

        // Wait for the operations to finish before proceeding
        checkError(clFinish(commandQueue),
                   "Failed to finish OpenCL command queue");

        // Get the time spent on the device
        checkError(getEventDuration(kernelExecutionEvent, kernelDuration),
                   "Failed to get event duration");
        deviceDuration += kernelDuration;

        // Update chunk size for the next pass
        chunkSize *= 2;
    }

    return EXIT_SUCCESS;
}

int runMergeSort(const cl_context &context, const cl_device_id &deviceId,
                 const cl_command_queue &commandQueue, const int *vector,
                 int *vectorDevice, const unsigned int vectorSize) {
    // Create buffers
    cl_int errorCode{};
    cl_mem deviceInputVector{};
    const auto _deviceInputVector{
        createAutoReleaseObject(clReleaseMemObject, deviceInputVector)};
    deviceInputVector = clCreateBuffer(
        context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
        vectorSize * sizeof(int), const_cast<int *>(vector), &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for input vector");

    cl_mem deviceOutputVector{};
    const auto _deviceOutputVector{
        createAutoReleaseObject(clReleaseMemObject, deviceOutputVector)};
    deviceOutputVector =
        clCreateBuffer(context, CL_MEM_READ_WRITE, vectorSize * sizeof(int),
                       nullptr, &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for output vector");

    // Create and build program from source
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};
    program = clCreateProgramWithSource(context, 1, &mergeSortKernelSource,
                                        nullptr, &errorCode);
    checkError(errorCode, "Failed to create OpenCL program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);
    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    // Create kernel
    cl_kernel kernel{};
    const auto _kernel{createAutoReleaseObject(clReleaseKernel, kernel)};
    kernel = clCreateKernel(program, "mergeSortKernel", &errorCode);
    checkError(errorCode, "Failed to create OpenCL merge kernel");

    // Call parallel merge sort
    double deviceDuration{};
    errorCode =
        parallelMergeSort(commandQueue, kernel, deviceInputVector,
                          deviceOutputVector, vectorSize, deviceDuration);
    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to execute merge sort\n";
        return EXIT_FAILURE;
    }

    std::cout << "OpenCL merge sort execution time: " << deviceDuration * 1e-6
              << " milliseconds\n";

    // Read the result back to the host
    checkError(clEnqueueReadBuffer(commandQueue, deviceInputVector, CL_TRUE, 0,
                                   vectorSize * sizeof(int), vectorDevice, 0,
                                   nullptr, nullptr),
               "Failed to copy vector from device to host");

    checkError(clFinish(commandQueue), "Failed to finish OpenCL command queue");

    return EXIT_SUCCESS;
}

int runSort(int *vector, const unsigned int vectorSize) {
    const auto hostStart{std::chrono::high_resolution_clock::now()};

    std::sort(vector, vector + vectorSize);

    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double, std::milli> hostDuration{hostEnd -
                                                                 hostStart};

    std::cout << "Host sort execution time: " << hostDuration.count()
              << " milliseconds\n";

    return EXIT_SUCCESS;
}

int runTest(const cl_device_id &deviceId) {
    const unsigned int vectorSize{1 << 20};
    const unsigned int alignment{16};

    auto alignedFreeDeleter = [](void *pointer) { aligned_free(pointer); };
    using aligned_vector_ptr =
        std::unique_ptr<int, decltype(alignedFreeDeleter)>;

    const aligned_vector_ptr vector{reinterpret_cast<int *>(aligned_malloc(
                                        vectorSize * sizeof(int), alignment)),
                                    alignedFreeDeleter};
    const aligned_vector_ptr vectorBitonicSortDevice{
        reinterpret_cast<int *>(
            aligned_malloc(vectorSize * sizeof(int), alignment)),
        alignedFreeDeleter};
    const aligned_vector_ptr vectorMergeSortDevice{
        reinterpret_cast<int *>(
            aligned_malloc(vectorSize * sizeof(int), alignment)),
        alignedFreeDeleter};

    fillVectorWithRandomNumbers(vector.get(), vectorSize);

    // Create OpenCL context and command queue
    cl_int errorCode{};
    cl_context context{};
    const auto _context{createAutoReleaseObject(clReleaseContext, context)};
    context =
        clCreateContext(nullptr, 1, &deviceId, nullptr, nullptr, &errorCode);
    checkError(errorCode, "Failed to create OpenCL context");

    cl_command_queue_properties commandQueueProperties[] = {
        CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE, 0};

    cl_command_queue commandQueue{};
    const auto _commandQueue{
        createAutoReleaseObject(clReleaseCommandQueue, commandQueue)};

    commandQueue = clCreateCommandQueueWithProperties(
        context, deviceId, commandQueueProperties, &errorCode);
    checkError(errorCode, "Failed to create OpenCL command queue");

    // Run bitonic sort
    errorCode = runBitonicSort(context, deviceId, commandQueue, vector.get(),
                               vectorBitonicSortDevice.get(), vectorSize);
    if (errorCode != EXIT_SUCCESS) {
        return errorCode;
    }

    // Run merge sort
    errorCode = runMergeSort(context, deviceId, commandQueue, vector.get(),
                             vectorMergeSortDevice.get(), vectorSize);
    if (errorCode != EXIT_SUCCESS) {
        return errorCode;
    }

    // Run host sort
    errorCode = runSort(vector.get(), vectorSize);
    if (errorCode != EXIT_SUCCESS) {
        return errorCode;
    }

    if (std::equal(vector.get(), vector.get() + vectorSize,
                   vectorBitonicSortDevice.get())) {
        std::cout << "Bitonic sort and host sort match!\n";
    } else {
        std::cout << "Bitonic sort and host sort do not match!\n";
    }

    if (std::equal(vector.get(), vector.get() + vectorSize,
                   vectorMergeSortDevice.get())) {
        std::cout << "Merge sort and host sort match!\n";
    } else {
        std::cout << "Merge sort and host sort do not match!\n";
    }

    return EXIT_SUCCESS;
}

int main() {
    std::srand(static_cast<unsigned int>(std::time(nullptr)));

    cl_uint platformCount{};
    checkError(clGetPlatformIDs(0, nullptr, &platformCount),
               "Failed to get platform count");

    const std::unique_ptr<cl_platform_id[]> platformIds{
        new cl_platform_id[platformCount]};
    checkError(clGetPlatformIDs(platformCount, platformIds.get(), nullptr),
               "Failed to get platform ids");

    for (cl_uint platformIndex{0}; platformIndex < platformCount;
         ++platformIndex) {
        size_t platformNameSize{};
        checkError(clGetPlatformInfo(platformIds[platformIndex],
                                     CL_PLATFORM_NAME, 0, nullptr,
                                     &platformNameSize),
                   "Failed to get platform name size");

        const std::unique_ptr<char[]> platformName{
            new char[platformNameSize + 1]};
        checkError(clGetPlatformInfo(platformIds[platformIndex],
                                     CL_PLATFORM_NAME, platformNameSize,
                                     platformName.get(), nullptr),
                   "Failed to get platform name");
        platformName[platformNameSize] = '\0';

        std::cout << "Platform " << platformIndex + 1 << ": "
                  << platformName.get() << "\n";

        cl_uint deviceCount{};
        checkError(clGetDeviceIDs(platformIds[platformIndex],
                                  CL_DEVICE_TYPE_ALL, 0, nullptr, &deviceCount),
                   "Failed to get device count");

        const std::unique_ptr<cl_device_id[]> deviceIds{
            new cl_device_id[deviceCount]};

        checkError(clGetDeviceIDs(platformIds[platformIndex],
                                  CL_DEVICE_TYPE_ALL, deviceCount,
                                  deviceIds.get(), nullptr),
                   "Failed to get device ids");

        for (cl_uint deviceIndex{0}; deviceIndex < deviceCount; ++deviceIndex) {
            size_t deviceNameSize{};
            checkError(clGetDeviceInfo(deviceIds[deviceIndex], CL_DEVICE_NAME,
                                       0, nullptr, &deviceNameSize),
                       "Failed to get device name size");

            const std::unique_ptr<char[]> deviceName{
                new char[deviceNameSize + 1]};
            checkError(clGetDeviceInfo(deviceIds[deviceIndex], CL_DEVICE_NAME,
                                       deviceNameSize, deviceName.get(),
                                       nullptr),
                       "Failed to get device name");
            deviceName[deviceNameSize] = '\0';

            std::cout << "Device " << deviceIndex + 1 << ": "
                      << deviceName.get() << "\n";

            const auto errorCode{runTest(deviceIds[deviceIndex])};

            if (errorCode != EXIT_SUCCESS) {
                std::cerr << "Failed to run test on the device: "
                          << deviceName.get() << "\n";
                continue;
            }

            std::cout << "\n";
        }
    }

    return EXIT_SUCCESS;
}
