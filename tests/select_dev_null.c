#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/select.h>
#include <errno.h>
#include <string.h>

#define BUFFER_SIZE 1024

int main() {
    int fd = open("/dev/null", O_RDONLY);
    if (fd == -1) {
        perror("Error opening /dev/null");
        exit(EXIT_FAILURE);
    }

    fd_set readfds;
    char buffer[BUFFER_SIZE];
    int ret;
    struct timeval tv;

    // Test 1: select() without timeout
    FD_ZERO(&readfds);
    FD_SET(fd, &readfds);

    printf("Test 1: select() on /dev/null without timeout\n");
    ret = select(fd + 1, &readfds, NULL, NULL, NULL);

    if (ret == -1) {
        perror("select error");
    } else if (ret) {
        printf("select() indicates /dev/null is ready for reading.\n");
    } else {
        printf("select() returned 0. This shouldn't happen with no timeout set.\n");
    }

    // Test 2: select() with a short timeout
    FD_ZERO(&readfds);
    FD_SET(fd, &readfds);
    tv.tv_sec = 1;
    tv.tv_usec = 0;

    printf("\nTest 2: select() on /dev/null with 1 second timeout\n");
    ret = select(fd + 1, &readfds, NULL, NULL, &tv);

    if (ret == -1) {
        perror("select error");
    } else if (ret) {
        printf("select() indicates /dev/null is ready for reading.\n");
    } else {
        printf("select() timed out.\n");
    }

    // Test 3: read() from /dev/null
    printf("\nTest 3: read() from /dev/null\n");
    ssize_t bytes_read = read(fd, buffer, BUFFER_SIZE);
    if (bytes_read >= 0) {
        printf("Read %zd bytes from /dev/null.\n", bytes_read);
    } else {
        printf("read() error: %s\n", strerror(errno));
    }

    close(fd);
    return 0;
}