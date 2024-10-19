#include <CL/cl.h>
#include <chrono>
#include <cmath>
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

// OpenCL kernel for matrix multiplication with non-square matrices using SIMD
//(cl_float4)
const char *multiplyMatricesSIMDKernelSource{R"(
__kernel void multiplyMatricesSIMDKernel(__global const float* matrixA,
                                         __global const float* matrixB,
                                         __global float* matrixC,
                                         const unsigned int heightA,
                                         const unsigned int widthA,
                                         const unsigned int widthB) {
    const unsigned int globalRowIndex = get_global_id(0);   
    const unsigned int globalColumnIndex = get_global_id(1);

    if (globalRowIndex < heightA && globalColumnIndex < widthB) {
        float4 sum = (float4)(0.0f, 0.0f, 0.0f, 0.0f);

        for (unsigned int groupIndex = 0; groupIndex < widthA; groupIndex += 4) {
            float4 groupA = vload4(0, &matrixA[globalRowIndex * widthA + groupIndex]);

            float4 groupB;
            groupB.x = matrixB[groupIndex * widthB + globalColumnIndex];
            groupB.y = matrixB[(groupIndex + 1) * widthB + globalColumnIndex];
            groupB.z = matrixB[(groupIndex + 2) * widthB + globalColumnIndex];
            groupB.w = matrixB[(groupIndex + 3) * widthB + globalColumnIndex];

            sum += groupA * groupB;
        }

        matrixC[globalRowIndex * widthB + globalColumnIndex] = sum.s0 + sum.s1 + sum.s2 + sum.s3;
    }
}
)"};

// OpenCL kernel for matrix multiplication with non-square matrices using SIMD
//(cl_float4) and transposition
const char *multiplyMatricesSIMDTransposedKernelSource{R"(
__kernel void multiplyMatricesSIMDTransposedKernel(__global const float4* matrixA,
                                                   __global const float4* matrixB,
                                                   __global float* matrixC,
                                                   const unsigned int heightA,
                                                   const unsigned int widthA,
                                                   const unsigned int heightB)
{
    const unsigned int globalRowIndex = get_global_id(0);
    const unsigned int globalColumnIndex = get_global_id(1);
    
    if (globalRowIndex < heightA && globalColumnIndex < heightB) {
        float4 sum = (float4)(0.0f, 0.0f, 0.0f, 0.0f);

        for (unsigned int groupIndex = 0; groupIndex < widthA / 4; groupIndex++) {
            sum += matrixA[globalRowIndex * widthA / 4 + groupIndex] * matrixB[globalColumnIndex * widthA / 4 + groupIndex];
        }
        
        matrixC[globalRowIndex * heightB + globalColumnIndex] = sum.s1 + sum.s0 + sum.s2 + sum.s3;
    }
}
)"};

// OpenCL kernel for matrix multiplication with non-square matrices using tiling
// and SIMD
const char *multiplyMatricesSIMDTiledKernelSource{R"(
__kernel void multiplyMatricesSIMDTiledKernel(__global const float* matrixA,
                                              __global const float* matrixB,
                                              __global float* matrixC,
                                              const unsigned int heightA,
                                              const unsigned int widthA,
                                              const unsigned int widthB,
                                              __local float4* tileA,
                                              __local float4* tileB,
                                              const unsigned int tileSize) {
    // Global work item indices (position in the output matrix C)
    const unsigned int globalRowIndex = get_global_id(0);   
    const unsigned int globalColumnIndex = get_global_id(1);

    // Local work item indices (position in the local tile)
    const unsigned int localRowIndex = get_local_id(0);
    const unsigned int localColumnIndex = get_local_id(1);

    // Accumulator for the output value
    float4 sum = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
    const unsigned int tilesCount = (widthA + tileSize - 1) / tileSize;

    // Loop over all tiles in matrix A and B
    for (unsigned int tileIndex = 0; tileIndex < tilesCount; ++tileIndex) {
        // Calculate the row and column index for loading data into local memory for matrix A
        const unsigned int aRowIndex = globalRowIndex;
        const unsigned int aColumnIndex = tileIndex * tileSize + localColumnIndex * 4;

        // Load matrix A tile into local memory
        if (aRowIndex < heightA && aColumnIndex + 3 < widthA) {
            tileA[localRowIndex * tileSize / 4 + localColumnIndex] = vload4(0, &matrixA[aRowIndex * widthA + aColumnIndex]);
        } else {
            tileA[localRowIndex * tileSize / 4 + localColumnIndex] = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
        }

        // Calculate the row and column index for loading data into local memory for matrix B
        const unsigned int bRowIndex = tileIndex * tileSize + localRowIndex * 4;
        const unsigned int bColumnIndex = globalColumnIndex;

        // Load matrix B tile into local memory (manually gather non-consecutive elements)
        if (bRowIndex + 3 < widthA && globalColumnIndex < widthB) {
            float4 groupB;
            groupB.x = matrixB[bRowIndex * widthB + globalColumnIndex];
            groupB.y = matrixB[(bRowIndex + 1) * widthB + globalColumnIndex];
            groupB.z = matrixB[(bRowIndex + 2) * widthB + globalColumnIndex];
            groupB.w = matrixB[(bRowIndex + 3) * widthB + globalColumnIndex];

            tileB[localRowIndex * tileSize / 4 + localColumnIndex] = groupB;
        } else {
            tileB[localRowIndex * tileSize / 4 + localColumnIndex] = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
        }

        // Wait for all threads to finish loading data into local memory
        barrier(CLK_LOCAL_MEM_FENCE);

        // Perform matrix multiplication for the current tile
        for (unsigned int elementIndex = 0; elementIndex < tileSize / 4; ++elementIndex) {
            sum += tileA[localRowIndex * tileSize / 4 + elementIndex] * tileB[elementIndex * tileSize / 4 + localColumnIndex];
        }

        // Wait for all threads before moving to the next tile
        barrier(CLK_LOCAL_MEM_FENCE);
    }

    // Write the result to the output matrix C
    if (globalRowIndex < heightA && globalColumnIndex < widthB) {
        matrixC[globalRowIndex * widthB + globalColumnIndex] = sum.s0 + sum.s1 + sum.s2 + sum.s3;
    }
}
)"};

// OpenCL kernel for matrix transpose
const char *transposeMatrixKernelSource{R"(
__kernel void transposeMatrixKernel(__global const float* inputMatrix,
                                    __global float* outputMatrix,
                                    const unsigned int height,
                                    const unsigned int width,
                                    __local float* tile,
									const unsigned int tileSize) {
    // Define local row and column indices
    const unsigned int localRowIndex = get_local_id(0);
    const unsigned int localColumnIndex = get_local_id(1);

    // Calculate global row and column indices
    unsigned int globalRowIndex = get_global_id(0);
    unsigned int globalColumnIndex = get_global_id(1);

    // Load data into local memory
    if (globalRowIndex < height && globalColumnIndex < width) {
        tile[localRowIndex * tileSize + localColumnIndex] = inputMatrix[globalRowIndex * width + globalColumnIndex];
    } else {
        tile[localRowIndex * tileSize + localColumnIndex] = 0.0f;
    }

    // Synchronize to ensure all threads have loaded data into local memory
    barrier(CLK_LOCAL_MEM_FENCE);

    // Calculate transposed row and column
    const unsigned int transposedRowIndex = get_group_id(1) * tileSize + localRowIndex;
    const unsigned int transposedColumnIndex = get_group_id(0) * tileSize + localColumnIndex;

    // Write transposed data to the output matrix
    if (transposedRowIndex < width && transposedColumnIndex < height) {
        outputMatrix[transposedRowIndex * height + transposedColumnIndex] = tile[localColumnIndex * tileSize + localRowIndex];
    }
}
)"};

// Host function for matrix multiplication (loop-based)
void multiplyMatrices(const float *matrixA, const float *matrixB,
                      float *matrixC, unsigned int heightA, unsigned int widthA,
                      unsigned int widthB) {
    if (matrixA == nullptr || matrixB == nullptr || matrixC == nullptr) {
        return;
    }

    for (unsigned int rowIndex{0}; rowIndex < heightA; ++rowIndex) {
        for (unsigned int columnIndex{0}; columnIndex < widthB; ++columnIndex) {
            float sum{0.0f};
            float c{0.0};

            for (unsigned int elementIndex{0}; elementIndex < widthA;
                 ++elementIndex) {
                const auto product{
                    matrixA[rowIndex * widthA + elementIndex] *
                    matrixB[elementIndex * widthB + columnIndex]};
                const auto y{product - c};
                const auto t{sum + y};

                c = (t - sum) - y;
                sum = t;
            }

            matrixC[rowIndex * widthB + columnIndex] = sum;
        }
    }
}

void fillMatrixWithRandomNumbers(float *matrix, unsigned int matrixSize) {
    if (matrix == nullptr) {
        return;
    }

    for (unsigned int elementIndex{0}; elementIndex < matrixSize;
         ++elementIndex) {
        matrix[elementIndex] = static_cast<float>(std::rand()) / RAND_MAX;
    }
}

size_t getLowerPowerOfTwo(size_t number) {
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

bool compareMatrices(const float *matrixA, const float *matrixB,
                     unsigned int matrixSize, float tolerance) {
    if (matrixA == nullptr || matrixB == nullptr) {
        return false;
    }

    for (unsigned int elementIndex{0}; elementIndex < matrixSize;
         ++elementIndex) {
        if (std::fabs(matrixA[elementIndex] - matrixB[elementIndex]) >
            tolerance) {
            std::cout << "Mismatch at index " << elementIndex
                      << std::setprecision(17)
                      << ". First value: " << matrixA[elementIndex]
                      << ", second value: " << matrixB[elementIndex] << "\n";

            return false;
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
                        size_t (&localWorkSize)[2]) {
    size_t maxLocalWorkSize{};
    checkError(clGetDeviceInfo(deviceId, CL_DEVICE_MAX_WORK_GROUP_SIZE,
                               sizeof(size_t), &maxLocalWorkSize, nullptr),
               "Failed to get max work group size");

    size_t preferredLocalWorkSize{};
    clGetKernelWorkGroupInfo(kernel, deviceId,
                             CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE,
                             sizeof(size_t), &preferredLocalWorkSize, nullptr);

    const size_t localWorkSizeX{std::min(
        preferredLocalWorkSize,
        getLowerPowerOfTwo(static_cast<size_t>(std::sqrt(maxLocalWorkSize))))};

    localWorkSize[0] = localWorkSizeX;
    localWorkSize[1] = localWorkSizeX;

    return CL_SUCCESS;
}

cl_int getEventDuration(cl_event event, cl_ulong &eventDuration) {
    cl_ulong deviceStart{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START,
                                       sizeof(cl_ulong), &deviceStart, nullptr),
               "Failed to get start time");

    cl_ulong deviceEnd{};
    checkError(clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END,
                                       sizeof(cl_ulong), &deviceEnd, nullptr),
               "Failed to get end time");

    eventDuration = deviceEnd - deviceStart;

    return CL_SUCCESS;
}

int runMultiplyMatricesSIMD(const cl_context &context,
                            const cl_device_id &deviceId,
                            const cl_command_queue &commandQueue,
                            cl_mem deviceMatrixA, cl_mem deviceMatrixB,
                            cl_mem deviceMatrixC, float *matrixCDevice,
                            unsigned int heightA, unsigned int widthA,
                            unsigned int widthB) {
    // Build kernel
    cl_int errorCode{};
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};

    program = clCreateProgramWithSource(
        context, 1, &multiplyMatricesSIMDKernelSource, nullptr, &errorCode);
    checkError(errorCode, "Failed to create program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);

    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    cl_kernel kernel{};
    const auto _kernel{createAutoReleaseObject(clReleaseKernel, kernel)};

    kernel = clCreateKernel(program, "multiplyMatricesSIMDKernel", &errorCode);
    checkError(errorCode, "Failed to create kernel");

    // Set kernel arguments
    checkError(clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceMatrixA),
               "Failed to set argument for matrix A");
    checkError(clSetKernelArg(kernel, 1, sizeof(cl_mem), &deviceMatrixB),
               "Failed to set argument for matrix B");
    checkError(clSetKernelArg(kernel, 2, sizeof(cl_mem), &deviceMatrixC),
               "Failed to set argument for matrix C");
    checkError(clSetKernelArg(kernel, 3, sizeof(unsigned int), &heightA),
               "Failed to set argument for matrix A height");
    checkError(clSetKernelArg(kernel, 4, sizeof(unsigned int), &widthA),
               "Failed to set argument for matrix A width");
    checkError(clSetKernelArg(kernel, 5, sizeof(unsigned int), &widthB),
               "Failed to set argument for matrix B width");

    const size_t globalWorkSize[2]{heightA, widthB};
    size_t localWorkSize[2]{};
    checkError(getLocalWorkSize(kernel, deviceId, localWorkSize),
               "Failed to get local work size");

    cl_event kernelExecutionEvent{};
    const auto _kernelExecutionEvent{
        createAutoReleaseObject(clReleaseEvent, kernelExecutionEvent)};

    checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 2, nullptr,
                                      globalWorkSize, localWorkSize, 0, nullptr,
                                      &kernelExecutionEvent),
               "Failed to enqueue NDRange kernel");

    // Wait for kernel completion
    checkError(clFinish(commandQueue), "Failed to wait for kernel completion");

    // Calculate and print the execution time (in milliseconds)
    cl_ulong deviceDuration{0};
    checkError(getEventDuration(kernelExecutionEvent, deviceDuration),
               "Failed to get event duration");

    std::cout << "OpenCL SIMD execution time: " << deviceDuration * 1e-6
              << " milliseconds\n";

    // Copy results back to host
    checkError(clEnqueueReadBuffer(commandQueue, deviceMatrixC, CL_TRUE, 0,
                                   heightA * widthB * sizeof(float),
                                   matrixCDevice, 0, nullptr, nullptr),
               "Failed to copy result matrix C to host");

    checkError(clFinish(commandQueue), "Failed to wait for buffer copy");

    return EXIT_SUCCESS;
}

int runMultiplyMatricesSIMDTransposed(
    const cl_context &context, const cl_device_id &deviceId,
    const cl_command_queue &commandQueue, cl_mem deviceMatrixA,
    cl_mem deviceMatrixB, cl_mem deviceMatrixC, float *matrixCDevice,
    unsigned int heightA, unsigned int widthA, unsigned int widthB) {
    // Create and build program
    cl_int errorCode{};
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};

    const char *programSources[]{transposeMatrixKernelSource,
                                 multiplyMatricesSIMDTransposedKernelSource};

    program = clCreateProgramWithSource(context, 2, programSources, nullptr,
                                        &errorCode);
    checkError(errorCode, "Failed to create program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);

    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    // Create and execute transpose kernel
    cl_kernel transposeKernel{};
    const auto _transposeKernel{
        createAutoReleaseObject(clReleaseKernel, transposeKernel)};

    transposeKernel =
        clCreateKernel(program, "transposeMatrixKernel", &errorCode);
    checkError(errorCode, "Failed to create kernel");

    cl_mem deviceMatrixBTransposed{};
    const auto _deviceMatrixBTrnasposed{
        createAutoReleaseObject(clReleaseMemObject, deviceMatrixBTransposed)};

    deviceMatrixBTransposed =
        clCreateBuffer(context, CL_MEM_READ_WRITE,
                       widthA * widthB * sizeof(float), nullptr, &errorCode);
    checkError(errorCode, "Failed to create buffer for transposed matrix B");

    size_t localWorkSize[2]{};
    checkError(getLocalWorkSize(transposeKernel, deviceId, localWorkSize),
               "Failed to get local work size");

    const size_t tileSize{localWorkSize[0]};
    const size_t tileMemorySize{tileSize * tileSize * sizeof(float)};

    // Set kernel arguments
    checkError(
        clSetKernelArg(transposeKernel, 0, sizeof(cl_mem), &deviceMatrixB),
        "Failed to set kernel argument for matrix B");
    checkError(clSetKernelArg(transposeKernel, 1, sizeof(cl_mem),
                              &deviceMatrixBTransposed),
               "Failed to set kernel argument for transposed matrix B");
    checkError(
        clSetKernelArg(transposeKernel, 2, sizeof(unsigned int), &widthA),
        "Failed to set kernel argument for matrix B height");
    checkError(
        clSetKernelArg(transposeKernel, 3, sizeof(unsigned int), &widthB),
        "Failed to set kernel argument for matrix B width");
    checkError(clSetKernelArg(transposeKernel, 4, tileMemorySize, nullptr),
               "Failed to set kernel argument for tile");
    checkError(
        clSetKernelArg(transposeKernel, 5, sizeof(unsigned int), &tileSize),
        "Failed to set kernel argument for tile size");

    size_t globalWorkSize[2]{((widthA + tileSize - 1) / tileSize) * tileSize,
                             ((widthB + tileSize - 1) / tileSize) * tileSize};

    cl_event kernelExecutionEvent{};
    const auto _kernelExecutionEvent{
        createAutoReleaseObject(clReleaseEvent, kernelExecutionEvent)};

    checkError(clEnqueueNDRangeKernel(commandQueue, transposeKernel, 2, nullptr,
                                      globalWorkSize, localWorkSize, 0, nullptr,
                                      &kernelExecutionEvent),
               "Failed to enqueue NDRange kernel");

    // Wait for kernel completion
    checkError(clFinish(commandQueue), "Failed to wait for kernel completion");

    // Calculate the execution time
    cl_ulong transposeDuration{0};
    checkError(getEventDuration(kernelExecutionEvent, transposeDuration),
               "Failed to get event duration");

    // Create and execute multiply kernel
    cl_kernel multiplyKernel{};
    const auto _multiplyKernel{
        createAutoReleaseObject(clReleaseKernel, multiplyKernel)};

    multiplyKernel = clCreateKernel(
        program, "multiplyMatricesSIMDTransposedKernel", &errorCode);
    checkError(errorCode, "Failed to create kernel");

    // Set kernel arguments
    checkError(
        clSetKernelArg(multiplyKernel, 0, sizeof(cl_mem), &deviceMatrixA),
        "Failed to set kernel argument for matrix A");
    checkError(clSetKernelArg(multiplyKernel, 1, sizeof(cl_mem),
                              &deviceMatrixBTransposed),
               "Failed to set kernel argument for transposed matrix B");
    checkError(
        clSetKernelArg(multiplyKernel, 2, sizeof(cl_mem), &deviceMatrixC),
        "Failed to set kernel argument for matrix C");
    checkError(
        clSetKernelArg(multiplyKernel, 3, sizeof(unsigned int), &heightA),
        "Failed to set kernel argument for matrix A height");
    checkError(clSetKernelArg(multiplyKernel, 4, sizeof(unsigned int), &widthA),
               "Failed to set kernel argument for matrix A width");
    checkError(clSetKernelArg(multiplyKernel, 5, sizeof(unsigned int), &widthB),
               "Failed to set kernel argument for matrix B width");

    globalWorkSize[0] = ((heightA + localWorkSize[0] - 1) / localWorkSize[0]) *
                        localWorkSize[0];
    globalWorkSize[1] =
        ((widthB + localWorkSize[1] - 1) / localWorkSize[1]) * localWorkSize[1];

    checkError(clEnqueueNDRangeKernel(commandQueue, multiplyKernel, 2, nullptr,
                                      globalWorkSize, localWorkSize, 0, nullptr,
                                      &kernelExecutionEvent),
               "Failed to enqueue NDRange kernel");

    // Wait for kernel completion
    checkError(clFinish(commandQueue), "Failed to wait for kernel completion");

    // Calculate the execution time
    cl_ulong multiplyDuration{0};
    checkError(getEventDuration(kernelExecutionEvent, multiplyDuration),
               "Failed to get event duration");

    const double deviceDuration{(transposeDuration + multiplyDuration) * 1e-6};

    std::cout << "OpenCL SIMD with trnasposition execution time: "
              << deviceDuration << " milliseconds\n";

    // Copy results back to host
    checkError(clEnqueueReadBuffer(commandQueue, deviceMatrixC, CL_TRUE, 0,
                                   heightA * widthB * sizeof(float),
                                   matrixCDevice, 0, nullptr, nullptr),
               "Failed to copy result matrix C to host");

    checkError(clFinish(commandQueue), "Failed to wait for buffer copy");

    return EXIT_SUCCESS;
}

int runMultiplyMatricesSIMDTiled(const cl_context &context,
                                 const cl_device_id &deviceId,
                                 const cl_command_queue &commandQueue,
                                 cl_mem deviceMatrixA, cl_mem deviceMatrixB,
                                 cl_mem deviceMatrixC, float *matrixCDevice,
                                 unsigned int heightA, unsigned int widthA,
                                 unsigned int widthB) {
    // Build kernel
    cl_int errorCode{};
    cl_program program{};
    const auto _program{createAutoReleaseObject(clReleaseProgram, program)};

    program = clCreateProgramWithSource(context, 1,
                                        &multiplyMatricesSIMDTiledKernelSource,
                                        nullptr, &errorCode);
    checkError(errorCode, "Failed to create program");

    errorCode =
        clBuildProgram(program, 1, &deviceId, nullptr, nullptr, nullptr);

    if (errorCode != CL_SUCCESS) {
        printBuildLog(program, deviceId);
        checkError(errorCode, "Failed to build OpenCL program");
    }

    cl_kernel kernel{};
    const auto _kernel{createAutoReleaseObject(clReleaseKernel, kernel)};

    kernel =
        clCreateKernel(program, "multiplyMatricesSIMDTiledKernel", &errorCode);
    checkError(errorCode, "Failed to create kernel");

    // Set kernel arguments
    size_t localWorkSize[2]{};
    checkError(getLocalWorkSize(kernel, deviceId, localWorkSize),
               "Failed to get local work size");
    localWorkSize[1] /= 4;
    const size_t tileSize{localWorkSize[0]};
    const size_t tileMemorySize{tileSize * tileSize * sizeof(float)};

    checkError(clSetKernelArg(kernel, 0, sizeof(cl_mem), &deviceMatrixA),
               "Failed to set argument for matrix A");
    checkError(clSetKernelArg(kernel, 1, sizeof(cl_mem), &deviceMatrixB),
               "Failed to set argument for matrix B");
    checkError(clSetKernelArg(kernel, 2, sizeof(cl_mem), &deviceMatrixC),
               "Failed to set argument for matrix C");
    checkError(clSetKernelArg(kernel, 3, sizeof(unsigned int), &heightA),
               "Failed to set argument for matrix A height");
    checkError(clSetKernelArg(kernel, 4, sizeof(unsigned int), &widthA),
               "Failed to set argument for matrix A width");
    checkError(clSetKernelArg(kernel, 5, sizeof(unsigned int), &widthB),
               "Failed to set argument for matrix B width");
    checkError(clSetKernelArg(kernel, 6, tileMemorySize, nullptr),
               "Failed to set argument for matrix A local memory");
    checkError(clSetKernelArg(kernel, 7, tileMemorySize, nullptr),
               "Failed to set argument for matrix B local memory");
    checkError(clSetKernelArg(kernel, 8, sizeof(unsigned int), &tileSize),
               "Failed to set kernel argument for tile size");

    const size_t globalWorkSize[2]{
        (heightA + tileSize - 1) / tileSize * tileSize,
        (widthB + tileSize - 1) / tileSize * tileSize};

    cl_event kernelExecutionEvent{};
    const auto _kernelExecutionEvent{
        createAutoReleaseObject(clReleaseEvent, kernelExecutionEvent)};

    checkError(clEnqueueNDRangeKernel(commandQueue, kernel, 2, nullptr,
                                      globalWorkSize, localWorkSize, 0, nullptr,
                                      &kernelExecutionEvent),
               "Failed to enqueue NDRange kernel");

    // Wait for kernel completion
    checkError(clFinish(commandQueue), "Failed to wait for kernel completion");

    // Calculate and print the execution time (in milliseconds)
    cl_ulong deviceDuration{0};
    checkError(getEventDuration(kernelExecutionEvent, deviceDuration),
               "Failed to get event duration");

    std::cout << "OpenCL SIMD with tiling execution time: "
              << deviceDuration * 1e-6 << " milliseconds\n";

    // Copy results back to host
    checkError(clEnqueueReadBuffer(commandQueue, deviceMatrixC, CL_TRUE, 0,
                                   heightA * widthB * sizeof(float),
                                   matrixCDevice, 0, nullptr, nullptr),
               "Failed to copy result matrix C to host");

    checkError(clFinish(commandQueue), "Failed to wait for buffer copy");

    return EXIT_SUCCESS;
}

int runMultiplyMatrices(const float *matrixA, const float *matrixB,
                        float *matrixC, const unsigned int heightA,
                        const unsigned int widthA, const unsigned int widthB) {
    const auto hostStart{std::chrono::high_resolution_clock::now()};

    multiplyMatrices(matrixA, matrixB, matrixC, heightA, widthA, widthB);

    const auto hostEnd{std::chrono::high_resolution_clock::now()};
    const std::chrono::duration<double, std::milli> hostDuration{hostEnd -
                                                                 hostStart};

    std::cout << "Loop-based host execution time: " << hostDuration.count()
              << " milliseconds\n";

    return EXIT_SUCCESS;
}

int runTest(const cl_device_id &deviceId) {
    // Dimensions should be multiple of 4
    const unsigned int heightA{1024};
    const unsigned int widthA{2048};
    const unsigned int widthB{768};
    const unsigned int alignment{16};

    auto alignedFreeDeleter = [](void *pointer) { aligned_free(pointer); };
    using aligned_matrix_ptr =
        std::unique_ptr<float[], decltype(alignedFreeDeleter)>;

    // Allocate host memory for matrices
    aligned_matrix_ptr matrixA{
        reinterpret_cast<float *>(
            aligned_malloc(heightA * widthA * sizeof(float), alignment)),
        alignedFreeDeleter};
    aligned_matrix_ptr matrixB{reinterpret_cast<float *>(aligned_malloc(
                                   widthA * widthB * sizeof(float), alignment)),
                               alignedFreeDeleter};
    aligned_matrix_ptr matrixC{
        reinterpret_cast<float *>(
            aligned_malloc(heightA * widthB * sizeof(float), alignment)),
        alignedFreeDeleter};
    aligned_matrix_ptr matrixCDeviceSIMD{
        reinterpret_cast<float *>(
            aligned_malloc(heightA * widthB * sizeof(float), alignment)),
        alignedFreeDeleter};
    aligned_matrix_ptr matrixCDeviceSIMDTransposed{
        reinterpret_cast<float *>(
            aligned_malloc(heightA * widthB * sizeof(float), alignment)),
        alignedFreeDeleter};
    aligned_matrix_ptr matrixCDeviceSIMDTiled{
        reinterpret_cast<float *>(
            aligned_malloc(heightA * widthB * sizeof(float), alignment)),
        alignedFreeDeleter};

    // Fill matrices with random values
    fillMatrixWithRandomNumbers(matrixA.get(), heightA * widthA);
    fillMatrixWithRandomNumbers(matrixB.get(), widthA * widthB);

    // OpenCL setup
    cl_context context{};
    const auto _context{createAutoReleaseObject(clReleaseContext, context)};

    cl_int errorCode{};
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
    cl_mem deviceMatrixA{};
    const auto _deviceMatrixA{
        createAutoReleaseObject(clReleaseMemObject, deviceMatrixA)};

    deviceMatrixA = clCreateBuffer(
        context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
        heightA * widthA * sizeof(float), matrixA.get(), &errorCode);
    checkError(errorCode, "Failed to create buffer for matrix A");

    cl_mem deviceMatrixB{};
    const auto _deviceMatrixB{
        createAutoReleaseObject(clReleaseMemObject, deviceMatrixB)};

    deviceMatrixB = clCreateBuffer(
        context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
        widthA * widthB * sizeof(float), matrixB.get(), &errorCode);
    checkError(errorCode, "Failed to create buffer for matrix B");

    cl_mem deviceMatrixC{};
    const auto _deviceMatrixC{
        createAutoReleaseObject(clReleaseMemObject, deviceMatrixC)};

    deviceMatrixC =
        clCreateBuffer(context, CL_MEM_WRITE_ONLY,
                       heightA * widthB * sizeof(float), nullptr, &errorCode);
    checkError(errorCode, "Failed to create buffer for matrix C");

    // Perform device SIMD matrix multiplication
    errorCode = runMultiplyMatricesSIMD(
        context, deviceId, commandQueue, deviceMatrixA, deviceMatrixB,
        deviceMatrixC, matrixCDeviceSIMD.get(), heightA, widthA, widthB);

    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to run SIMD matrix multiplication \n";
    }

    // Perform device SIMD with transposition matrix multiplication
    errorCode = runMultiplyMatricesSIMDTransposed(
        context, deviceId, commandQueue, deviceMatrixA, deviceMatrixB,
        deviceMatrixC, matrixCDeviceSIMDTransposed.get(), heightA, widthA,
        widthB);

    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to run SIMD with transposition matrix "
                     "multiplication \n";
    }

    // Perform device SIMD tiled matrix multiplication
    errorCode = runMultiplyMatricesSIMDTiled(
        context, deviceId, commandQueue, deviceMatrixA, deviceMatrixB,
        deviceMatrixC, matrixCDeviceSIMDTiled.get(), heightA, widthA, widthB);

    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to run SIMD with tiling matrix multiplication \n";
    }

    // Perform host matrix multiplication
    errorCode = runMultiplyMatrices(matrixA.get(), matrixB.get(), matrixC.get(),
                                    heightA, widthA, widthB);

    if (errorCode != EXIT_SUCCESS) {
        std::cerr << "Failed to run host matrices multiplication \n";
    }

    // Compare results
    const float tolerance{1e-3f};

    if (compareMatrices(matrixC.get(), matrixCDeviceSIMD.get(),
                        heightA * widthB, tolerance)) {
        std::cout << "Host loop-based and device SIMD matrix multiplication "
                     "results match!"
                  << std::endl;
    } else {
        std::cout << "Host loop-based and device SIMD matrix multiplication "
                     "results do NOT match!"
                  << std::endl;
    }

    if (compareMatrices(matrixC.get(), matrixCDeviceSIMDTransposed.get(),
                        heightA * widthB, tolerance)) {
        std::cout
            << "Host loop-based and device SIMD with transposition matrix "
               "multiplication results match!"
            << std::endl;
    } else {
        std::cout
            << "Host loop-based and device SIMD with transposition matrix "
               "multiplication results do NOT match!"
            << std::endl;
    }

    if (compareMatrices(matrixC.get(), matrixCDeviceSIMDTiled.get(),
                        heightA * widthB, tolerance)) {
        std::cout << "Host loop-based and device SIMD with tiling matrix "
                     "multiplication results match!"
                  << std::endl;
    } else {
        std::cout << "Host loop-based and device SIMD with tiling matrix "
                     "multiplication results do NOT match!"
                  << std::endl;
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
