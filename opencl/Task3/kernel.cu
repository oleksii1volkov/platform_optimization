#include <CL/cl.h>
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

// OpenCL kernel using SIMD (cl_float4) and shared (local) memory for reduction
const char *kernelSource{R"(
__kernel void reduceVectorSIMDKernel(__global const float4 *inputVector,
                                     __global float4 *partialSumsVector,
                                     __local float4* localData,
                                     const unsigned int inputVectorSize) {
    const unsigned int localId = get_local_id(0);
    const unsigned int globalId = get_global_id(0);
    
    // Initialize local data
    if (globalId < inputVectorSize) {
        localData[localId] = inputVector[globalId];
    } else {
        localData[localId] = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    // Perform reduction within local data
    for (unsigned int stride = get_local_size(0) / 2; stride > 0; stride >>= 1) {
        if (localId < stride) {
            localData[localId] += localData[localId + stride];
        }

        barrier(CLK_LOCAL_MEM_FENCE);
    }

    if (localId == 0) {
        partialSumsVector[get_group_id(0)] = localData[0];
    }
}
)"};

float reduceVector(const float *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return 0.0f;
    }

    float sum{0.0f};

    for (unsigned int elementIndex{0}; elementIndex < vectorSize;
         ++elementIndex) {
        sum += vector[elementIndex];
    }

    return sum;
}

float reduceVectorKahan(const float *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return 0.0f;
    }

    auto sum{vector[0]};
    float c{0.0};

    for (unsigned int elementIndex{1}; elementIndex < vectorSize;
         ++elementIndex) {
        const auto y{vector[elementIndex] - c};
        const auto t{sum + y};

        c = (t - sum) - y;
        sum = t;
    }

    return sum;
}

size_t getGreaterOrEqualPowerOfTwo(size_t number) {
    if (number == 0) {
        return 1;
    }

    number--;
    number |= number >> 1;
    number |= number >> 2;
    number |= number >> 4;
    number |= number >> 8;
    number |= number >> 16;

    if (sizeof(size_t) > 4) {
        number |= number >> 32;
    }

    return number + 1;
}

void fillVectorWithRandomNumbers(cl_float4 *vector, unsigned int vectorSize) {
    for (unsigned int groupIndex{0}; groupIndex < vectorSize; ++groupIndex) {
        for (unsigned int elementIndex{0}; elementIndex < 4; ++elementIndex) {
            vector[groupIndex].s[elementIndex] =
                static_cast<float>(std::rand()) / RAND_MAX;
        }
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

int runTest(const cl_device_id &deviceId) {
    const unsigned int vectorSize{1 << 20};
    const unsigned int alignment{16};

    auto alignedFreeDeleter = [](void *pointer) { aligned_free(pointer); };
    using aligned_vector_ptr =
        std::unique_ptr<cl_float4[], decltype(alignedFreeDeleter)>;

    const aligned_vector_ptr inputVector{
        reinterpret_cast<cl_float4 *>(
            aligned_malloc(vectorSize * sizeof(cl_float4), alignment)),
        alignedFreeDeleter};

    fillVectorWithRandomNumbers(inputVector.get(), vectorSize);

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

    // Create memory buffers on the device
    cl_mem deviceInputVector{};
    const auto _deviceInputVector{
        createAutoReleaseObject(clReleaseMemObject, deviceInputVector)};
    deviceInputVector = clCreateBuffer(
        context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
        vectorSize * sizeof(cl_float4), inputVector.get(), &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for input vector");

    cl_mem devicePartialSumsVector{};
    const auto _devicePartialSumsVector{
        createAutoReleaseObject(clReleaseMemObject, devicePartialSumsVector)};
    devicePartialSumsVector =
        clCreateBuffer(context, CL_MEM_READ_WRITE,
                       vectorSize * sizeof(cl_float4), nullptr, &errorCode);
    checkError(errorCode,
               "Failed to create OpenCL buffer for partial sums vector");

    // Create program from source
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};
    program = clCreateProgramWithSource(context, 1, &kernelSource, nullptr,
                                        &errorCode);
    checkError(errorCode, "Failed to create OpenCL program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);

    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    cl_kernel kernel{};
    const auto _kernel{createAutoReleaseObject(clReleaseKernel, kernel)};
    kernel = clCreateKernel(program, "reduceVectorSIMDKernel", &errorCode);
    checkError(errorCode, "Failed to create OpenCL kernel");

    size_t localWorkSize{64};
    size_t globalWorkSize{getGreaterOrEqualPowerOfTwo(vectorSize)};
    double deviceDuration{0.0};

    // Perform multiple reduction stages until one element is left
    for (unsigned int currentVectorSize{vectorSize}; currentVectorSize > 1;) {
        if (globalWorkSize < localWorkSize) {
            localWorkSize = globalWorkSize;
        }

        // Round up globalWorkSize to a multiple of localWorkSize
        globalWorkSize =
            ((globalWorkSize + localWorkSize - 1) / localWorkSize) *
            localWorkSize;

        const size_t groupsCount{(currentVectorSize + localWorkSize - 1) /
                                 localWorkSize};
        cl_event event{};
        const auto _event{createAutoReleaseObject(clReleaseEvent, event)};

        // Set kernel arguments
        const size_t localMemorySize{localWorkSize * sizeof(cl_float4)};

        checkError(
            clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceInputVector),
            "Failed to set kernel argument for input vector");
        checkError(
            clSetKernelArg(kernel, 1, sizeof(cl_mem), &devicePartialSumsVector),
            "Failed to set kernel argument for partial sums vector");
        checkError(clSetKernelArg(kernel, 2, localMemorySize, nullptr),
                   "Failed to set kernel argument for local memory buffer");
        checkError(
            clSetKernelArg(kernel, 3, sizeof(unsigned int), &currentVectorSize),
            "Failed to set kernel argument for vector size");

        // Launch the kernel
        checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 1, nullptr,
                                          &globalWorkSize, &localWorkSize, 0,
                                          nullptr, &event),
                   "Failed to execute kernel");
        checkError(clFinish(commandQueue), "Failed to finish command queue");

        // Get the time spent on the device
        cl_ulong deviceStart{};
        checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START,
                                           sizeof(cl_ulong), &deviceStart,
                                           nullptr),
                   "Failed to get start time");

        cl_ulong deviceEnd{};
        checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END,
                                           sizeof(cl_ulong), &deviceEnd,
                                           nullptr),
                   "Failed to get end time");

        deviceDuration += deviceEnd - deviceStart;

        // Swap the input and output buffers for the next stage
        std::swap(deviceInputVector, devicePartialSumsVector);

        // Update the size for the next reduction stage
        currentVectorSize = static_cast<unsigned int>(groupsCount);
        globalWorkSize = getGreaterOrEqualPowerOfTwo(currentVectorSize);
    }

    std::swap(deviceInputVector, devicePartialSumsVector);

    // Final reduction on CPU
    cl_float4 devicePartialSums{};
    checkError(clEnqueueReadBuffer(commandQueue, devicePartialSumsVector,
                                   CL_TRUE, 0, sizeof(cl_float4),
                                   &devicePartialSums, 0, nullptr, nullptr),
               "Failed to read final partial sums from device");

    const float deviceSum{devicePartialSums.s[0] + devicePartialSums.s[1] +
                          devicePartialSums.s[2] + devicePartialSums.s[3]};

    // Get the time spent on the host
    const auto hostStart{std::chrono::high_resolution_clock::now()};

    const float hostSum{reduceVectorKahan(
        reinterpret_cast<float *>(inputVector.get()), vectorSize * 4)};

    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double, std::milli> hostDuration{hostEnd -
                                                                 hostStart};

    std::cout << "OpenCL SIMD reduction execution time: "
              << deviceDuration * 1e-6 << " milliseconds\n";

    std::cout << "Loop-based host reduction execution time: "
              << hostDuration.count() << " milliseconds\n";

    std::cout << "Device sum: " << std::setprecision(17) << deviceSum << "\n";
    std::cout << "Host sum: " << std::setprecision(17) << hostSum << "\n";

    const float tolerance{1.0f};

    if (std::abs(deviceSum - hostSum) < tolerance) {
        std::cout << "The device sum matches the host sum!\n";
    } else {
        std::cout << "The device sum does not match the host sum!\n";
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
