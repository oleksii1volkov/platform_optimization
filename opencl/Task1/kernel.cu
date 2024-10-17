#include <CL/cl.h>
#include <chrono>
#include <cmath>
#include <cstdlib>
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

// OpenCL kernel using SIMD (cl_float4)
const char *kernelSource = R"(
__kernel void addVectorsSIMDKernel(__global const float4 *vectorA,
                                   __global const float4 *vectorB,
                                   __global float4 *vectorC,
                                   const unsigned int vectorSize) {
    const unsigned int elementIndex = get_global_id(0);
    
    if (elementIndex < vectorSize) {
        vectorC[elementIndex] = vectorA[elementIndex] + vectorB[elementIndex];
    }
}
)";

void addVectors(const cl_float4 *vectorA, const cl_float4 *vectorB,
                cl_float4 *vectorC, unsigned int vectorSize) {
    if (vectorA == nullptr || vectorB == nullptr || vectorC == nullptr) {
        return;
    }

    for (unsigned int groupIndex{0}; groupIndex < vectorSize; ++groupIndex) {
        for (unsigned int elementIndex{0}; elementIndex < 4; ++elementIndex) {
            vectorC[groupIndex].s[elementIndex] =
                vectorA[groupIndex].s[elementIndex] +
                vectorB[groupIndex].s[elementIndex];
        }
    }
}

void fillVectorWithRandomNumbers(cl_float4 *vector, unsigned int vectorSize) {
    if (vector == nullptr) {
        return;
    }

    for (unsigned int groupIndex{0}; groupIndex < vectorSize; ++groupIndex) {
        for (unsigned int elementIndex{0}; elementIndex < 4; ++elementIndex) {
            vector[groupIndex].s[elementIndex] =
                static_cast<float>(std::rand()) / RAND_MAX;
        }
    }
}

bool compareVectors(const cl_float4 *vectorA, const cl_float4 *vectorB,
                    size_t vectorSize) {
    if (vectorA == nullptr || vectorB == nullptr) {
        return false;
    }

    for (unsigned int groupIndex{0}; groupIndex < vectorSize; ++groupIndex) {
        for (unsigned int elementIndex{0}; elementIndex < 4; ++elementIndex) {
            if (vectorA[groupIndex].s[elementIndex] !=
                vectorB[groupIndex].s[elementIndex]) {
                std::cout << "Error: Result mismatch at index " << groupIndex
                          << " element " << elementIndex << ". First value: "
                          << vectorA[groupIndex].s[elementIndex]
                          << ". Second value: "
                          << vectorB[groupIndex].s[elementIndex] << ".\n";
                return false;
            }
        }
    }

    return true;
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

size_t getLowerOrEqualPowerOfTwo(size_t number) {
    if (number == 0) {
        return 0;
    }

    number |= number >> 1;
    number |= number >> 2;
    number |= number >> 4;
    number |= number >> 8;
    number |= number >> 16;

    if (sizeof(size_t) > 4) {
        number |= number >> 32;
    }

    return number - (number >> 1);
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

cl_int getLocalWorkSize(const cl_kernel &kernel, const cl_device_id &deviceId,
                        size_t &localWorkSize) {
    size_t maxLocalWorkSize{};
    checkError(clGetDeviceInfo(deviceId, CL_DEVICE_MAX_WORK_GROUP_SIZE,
                               sizeof(size_t), &maxLocalWorkSize, nullptr),
               "Failed to get max work group size");

    size_t preferredLocalWorkSize{};
    checkError(clGetKernelWorkGroupInfo(
                   kernel, deviceId,
                   CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE, sizeof(size_t),
                   &preferredLocalWorkSize, nullptr),
               "Failed to get kernel work group info");

    localWorkSize = std::min(preferredLocalWorkSize,
                             getLowerOrEqualPowerOfTwo(static_cast<size_t>(
                                 std::sqrt(maxLocalWorkSize))));

    return CL_SUCCESS;
}

int runTest(const cl_device_id &deviceId) {
    const unsigned int vectorSize{1 << 20};
    const unsigned int alignment{16};

    auto alignedFreeDeleter = [](void *pointer) { aligned_free(pointer); };
    using aligned_vector_ptr =
        std::unique_ptr<cl_float4[], decltype(alignedFreeDeleter)>;

    // Allocate host memory
    const aligned_vector_ptr vectorA{
        reinterpret_cast<cl_float4 *>(
            aligned_malloc(vectorSize * sizeof(cl_float4), alignment)),
        alignedFreeDeleter};
    const aligned_vector_ptr vectorB{
        reinterpret_cast<cl_float4 *>(
            aligned_malloc(vectorSize * sizeof(cl_float4), alignment)),
        alignedFreeDeleter};
    const aligned_vector_ptr vectorC{
        reinterpret_cast<cl_float4 *>(
            aligned_malloc(vectorSize * sizeof(cl_float4), alignment)),
        alignedFreeDeleter};
    const aligned_vector_ptr vectorCDevice{
        reinterpret_cast<cl_float4 *>(
            aligned_malloc(vectorSize * sizeof(cl_float4), alignment)),
        alignedFreeDeleter};

    // Fill the vectors with random numbers
    fillVectorWithRandomNumbers(vectorA.get(), vectorSize);
    fillVectorWithRandomNumbers(vectorB.get(), vectorSize);

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

    // Build kernel program
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
    kernel = clCreateKernel(program, "addVectorsSIMDKernel", &errorCode);
    checkError(errorCode, "Failed to create OpenCL kernel");

    // Create memory buffers on the device
    cl_mem deviceVectorA{};
    const auto _deviceVectorA{
        createAutoReleaseObject(clReleaseMemObject, deviceVectorA)};
    deviceVectorA = clCreateBuffer(
        context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
        vectorSize * sizeof(cl_float4), vectorA.get(), &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for vector A");

    cl_mem deviceVectorB{};
    const auto _deviceVectorB{
        createAutoReleaseObject(clReleaseMemObject, deviceVectorB)};
    deviceVectorB = clCreateBuffer(
        context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
        vectorSize * sizeof(cl_float4), vectorB.get(), &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for vector B");

    cl_mem deviceVectorC{};
    const auto _deviceVectorC{
        createAutoReleaseObject(clReleaseMemObject, deviceVectorC)};
    deviceVectorC =
        clCreateBuffer(context, CL_MEM_WRITE_ONLY,
                       vectorSize * sizeof(cl_float4), nullptr, &errorCode);
    checkError(errorCode, "Failed to create OpenCL buffer for vector C");

    // Set kernel arguments
    checkError(clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceVectorA),
               "Failed to set kernel argument for vector A");
    checkError(clSetKernelArg(kernel, 1, sizeof(cl_mem), &deviceVectorB),
               "Failed to set kernel argument for vector B");
    checkError(clSetKernelArg(kernel, 2, sizeof(cl_mem), &deviceVectorC),
               "Failed to set kernel argument for vector C");
    checkError(clSetKernelArg(kernel, 3, sizeof(unsigned int), &vectorSize),
               "Failed to set kernel argument for vector size");

    // Set global and local workgroup sizes
    size_t localWorkSize{};
    checkError(getLocalWorkSize(kernel, deviceId, localWorkSize),
               "Failed to get local work size");
    size_t globalWorkSize{getGreaterOrEqualPowerOfTwo(vectorSize)};
    globalWorkSize =
        ((globalWorkSize + localWorkSize - 1) / localWorkSize) * localWorkSize;

    // Measure OpenCL SIMD execution
    cl_event event{};
    const auto _event{createAutoReleaseObject(clReleaseEvent, event)};

    // Execute the kernel
    checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 1, nullptr,
                                      &globalWorkSize, &localWorkSize, 0,
                                      nullptr, &event),
               "Failed to execute OpenCL kernel");

    checkError(clFinish(commandQueue), "Failed to finish OpenCL command queue");

    // Retrieve profiling information
    cl_ulong deviceStart{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START,
                                       sizeof(cl_ulong), &deviceStart, nullptr),
               "Failed to get event profiling start");

    cl_ulong deviceEnd{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END,
                                       sizeof(cl_ulong), &deviceEnd, nullptr),
               "Failed to get event profiling end");

    // Calculate and print the execution time (in milliseconds)
    double deviceDuration{(deviceEnd - deviceStart) * 1e-6};

    std::cout << "OpenCL SIMD execution time: " << deviceDuration
              << " milliseconds\n";

    // Copy the result from device to host
    checkError(clEnqueueReadBuffer(commandQueue, deviceVectorC, CL_TRUE, 0,
                                   vectorSize * sizeof(cl_float4),
                                   vectorCDevice.get(), 0, NULL, NULL),
               "Failed to copy vector C from the device");

    checkError(clFinish(commandQueue), "Failed to finish OpenCL command queue");

    // Validate results using a simple loop-based vector addition
    const auto hostStart{std::chrono::high_resolution_clock::now()};

    addVectors(vectorA.get(), vectorB.get(), vectorC.get(), vectorSize);

    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double, std::milli> hostDuration{hostEnd -
                                                                 hostStart};

    std::cout << "Loop-based host execution time: " << hostDuration.count()
              << " milliseconds\n";

    // Check for correctness
    if (compareVectors(vectorC.get(), vectorCDevice.get(), vectorSize)) {
        std::cout << "Host and device results match!\n";
    } else {
        std::cout << "Host and device results do not match!\n";
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
