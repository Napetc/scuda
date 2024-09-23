#include <arpa/inet.h>
#include <cstring>
#include <dlfcn.h>
#include <functional>
#include <iostream>
#include <netdb.h>
#include <nvml.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

#include <unordered_map>

#include "api.h"
#include "codegen/gen_client.h"

int sockfd = -1;
char *port;

int open_rpc_client()
{
    // if socket is already opened, return our socket.
    if (sockfd != -1)
    {
        // << "socket already opened" << std::endl;

        return sockfd;
    }

    // << "opening tcp socket..." << std::endl;

    char *server_ip = getenv("SCUDA_SERVER");
    if (server_ip == NULL)
    {
        printf("SCUDA_SERVER environment variable not set\n");
        std::exit(1);
    }

    char *p = getenv("SCUDA_PORT");

    if (p == NULL)
    {
        port = (char *)"14833";
    }
    else
    {
        port = p;
        // << "using SCUDA_PORT: " << port << std::endl;
    }

    addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(server_ip, port, &hints, &res) != 0)
    {
        printf("getaddrinfo failed\n");
        return -1;
    }

    sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sockfd == -1)
    {
        printf("socket creation failed...\n");
        return -1;
    }

    if (connect(sockfd, res->ai_addr, res->ai_addrlen) != 0)
    {
        printf("connection with the server failed...\n");
        return -1;
    }
    return sockfd;
}

pthread_mutex_t mutex;
pthread_cond_t cond;

int rpc_start_request(const unsigned int op)
{
    static int next_request_id = 1;

    open_rpc_client();

    // write the request atomically
    pthread_mutex_lock(&mutex);

    int request_id = next_request_id++;

    if (write(sockfd, &request_id, sizeof(int)) < 0 ||
        write(sockfd, &op, sizeof(unsigned int)) < 0)
    {
        pthread_mutex_unlock(&mutex);
        return -1;
    }

    return request_id;
}

int rpc_write(const void *data, const size_t size)
{
    if (write(sockfd, data, size) < 0)
    {
        pthread_mutex_unlock(&mutex);
        return -1;
    }
    return 0;
}

int rpc_read(void *data, const size_t size)
{
    if (read(sockfd, data, size) < 0)
    {
        pthread_mutex_unlock(&mutex);
        return -1;
    }
    return 0;
}

int rpc_wait_for_response(const unsigned int request_id)
{
    static int active_response_id = -1;

    // wait for the response
    while (true)
    {
        while (active_response_id != request_id && active_response_id != -1)
            pthread_cond_wait(&cond, &mutex);

        // we currently own mutex. if active response id is -1, read the response id
        if (active_response_id == -1)
        {
            if (read(sockfd, &active_response_id, sizeof(int)) < 0)
            {
                pthread_mutex_unlock(&mutex);
                return -1;
            }

            if (active_response_id != request_id)
            {
                pthread_cond_broadcast(&cond);
                continue;
            }
        }

        active_response_id = -1;
        return 0;
    }
}

int rpc_end_request(void *result, const unsigned int request_id)
{
    if (read(sockfd, result, sizeof(nvmlReturn_t)) < 0)
        return -1;

    pthread_mutex_unlock(&mutex);
    return 0;
}

void close_rpc_client()
{
    close(sockfd);
    sockfd = 0;
}

void *dlsym(void *handle, const char *name) __THROW
{
    void *func = get_function_pointer(name);

    if (func != nullptr)
        return func;

    static void *(*real_dlsym)(void *, const char *) = NULL;
    if (real_dlsym == NULL)
    {
        // avoid calling dlsym recursively; use dlvsym to resolve dlsym itself
        real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym",
                                                             "GLIBC_2.2.5");
    }

    if (!strcmp(name, "dlsym"))
        return (void *)dlsym;

    // if func symbol is not found in the handler mappings, return the real dlsym
    // resolution
    return real_dlsym(handle, name);
}
