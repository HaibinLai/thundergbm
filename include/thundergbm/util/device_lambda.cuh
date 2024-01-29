//
// Created by jiashuai on 18-1-19.
//

#ifndef THUNDERGBM_DEVICE_LAMBDA_H
#define THUNDERGBM_DEVICE_LAMBDA_H

#include "thundergbm/common.h"

template<typename L>
__global__ void lambda_kernel(size_t len, L lambda) {
    for (size_t i = blockIdx.x * blockDim.x + threadIdx.x; i < len; i += blockDim.x * gridDim.x) {
        lambda(i);
    }
}

template<typename L>
__global__ void anonymous_kernel_k(L lambda) {
    lambda();
}

template<typename L>
__global__ void lambda_2d_sparse_kernel(const int *len2, L lambda) {
    int i = blockIdx.x;
    int begin = len2[i];
    int end = len2[i + 1];
    for (int j = begin + blockIdx.y * blockDim.x + threadIdx.x; j < end; j += blockDim.x * gridDim.y) {
        lambda(i, j);
    }
}

template<typename L>
__global__ void lambda_2d_maximum_sparse_kernel(const int *len2, const int maximum, L lambda) {
    int i = blockIdx.x;
    int begin = len2[i];
    int end = len2[i + 1];
    int interval = (end - begin) / maximum;
    for (int j = begin + blockIdx.y * blockDim.x + threadIdx.x; j < end; j += blockDim.x * gridDim.y) {
        lambda(i, j, interval);
    }
}

///p100 has 56 MPs, using 32*56 thread blocks, one MP supports 2048 threads
//a6000 has 84 mps
template<int NUM_BLOCK = 32 * 84, int BLOCK_SIZE = 256, typename L>
inline void device_loop(size_t len, L lambda) {
    if (len > 0) {
        lambda_kernel << < NUM_BLOCK, BLOCK_SIZE >> > (len, lambda);
        cudaDeviceSynchronize();
        /*cudaError_t error = cudaPeekAtLastError();*/
        if(cudaPeekAtLastError() == cudaErrorInvalidResourceHandle){
            cudaGetLastError();
            LOG(INFO) << "warning: cuda invalid resource handle, potential issue of driver version and cuda version mismatch";
        } else {
            CUDA_CHECK(cudaPeekAtLastError());
        }
    }
}

template<typename L>
inline void anonymous_kernel(L lambda, size_t num_fv, size_t smem_size = 0, int NUM_BLOCK = 32 * 84, int BLOCK_SIZE = 256) {
    size_t tmp_num_block = num_fv / (BLOCK_SIZE * 8);
    NUM_BLOCK = std::min(NUM_BLOCK, (int)std::max(tmp_num_block, (size_t)32));
    anonymous_kernel_k<< < NUM_BLOCK, BLOCK_SIZE, smem_size >> > (lambda);
    cudaDeviceSynchronize();
    if(cudaPeekAtLastError() == cudaErrorInvalidResourceHandle){
        cudaGetLastError();
        LOG(INFO) << "warning: cuda invalid resource handle, potential issue of driver version and cuda version mismatch";
    } else {
        CUDA_CHECK(cudaPeekAtLastError());
    }    
}

/**
 * @brief: (len1 x NUM_BLOCK) is the total number of blocks; len2 is an array of lengths.
 */
template<typename L>
void device_loop_2d(int len1, const int *len2, L lambda, unsigned int NUM_BLOCK = 4 * 84,
                    unsigned int BLOCK_SIZE = 256) {
    if (len1 > 0) {
        lambda_2d_sparse_kernel << < dim3(len1, NUM_BLOCK), BLOCK_SIZE >> > (len2, lambda);
        cudaDeviceSynchronize();
        CUDA_CHECK(cudaPeekAtLastError());
    }
}

/**
 * @brief: (len1 x NUM_BLOCK) is the total number of blocks; len2 is an array of lengths.
 */
template<typename L>
void device_loop_2d_with_maximum(int len1, const int *len2, const int maximum, L lambda,
                                 unsigned int NUM_BLOCK = 4 * 84,
                                 unsigned int BLOCK_SIZE = 256) {
    if (len1 > 0) {
        lambda_2d_maximum_sparse_kernel << < dim3(len1, NUM_BLOCK), BLOCK_SIZE >> > (len2, maximum, lambda);
        cudaDeviceSynchronize();
        CUDA_CHECK(cudaPeekAtLastError());
    }
}

//for sparse formate bin id
//func for new sparse loop 
template<typename L>
__global__ void lambda_hist_csr_root_kernel(const int *csr_row_ptr, L lambda) {

    int i = blockIdx.x;
    int begin = csr_row_ptr[i];
    int end = csr_row_ptr[i + 1];
    for (int j = begin + blockIdx.y * blockDim.x + threadIdx.x; j < end; j += blockDim.x * gridDim.y) {
        //i for instance
        //j for feature
        lambda(i, j );
    }
}



template<typename L>
void device_loop_hist_csr_root(int n_instances, const int *csr_row_ptr, L lambda , unsigned int NUM_BLOCK = 4 * 84,
                    unsigned int BLOCK_SIZE = 256) {
    if (n_instances > 0) {
        lambda_hist_csr_root_kernel << < dim3(n_instances, NUM_BLOCK), BLOCK_SIZE >> > (csr_row_ptr, lambda);
        cudaDeviceSynchronize();
        CUDA_CHECK(cudaPeekAtLastError());
    }
}

template<typename L>
__global__ void lambda_hist_csr_node_kernel(L lambda) {
    int i = blockIdx.x;
    int current_pos = blockIdx.y * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.y;
    lambda(i,current_pos,stride);
}

template<typename L>
void device_loop_hist_csr_node(int n_instances, const int *csr_row_ptr, L lambda , unsigned int NUM_BLOCK = 4 * 84,
                    unsigned int BLOCK_SIZE = 256) {
    if (n_instances > 0) {
        lambda_hist_csr_node_kernel << < dim3(n_instances, NUM_BLOCK), BLOCK_SIZE >> > (lambda);
        cudaDeviceSynchronize();
        CUDA_CHECK(cudaPeekAtLastError());
    }
}


#endif //THUNDERGBM_DEVICE_LAMBDA_H
