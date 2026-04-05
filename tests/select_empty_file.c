#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/select.h>
#include <errno.h>
#include <string.h>

#define BUFFER_SIZE 1024

int main() {
    const char* filename = "empty_file.txt";
    int fd = open(filename, O_RDONLY | O_CREAT, 0644);
    if (fd == -1) {
        perror("Error opening file");
        exit(EXIT_FAILURE);
    }

    fd_set readfds;
    char buffer[BUFFER_SIZE];
    int ret;

    FD_ZERO(&readfds);
    FD_SET(fd, &readfds);

    printf("Checking if the empty file is ready for reading...\n");
    ret = select(fd + 1, &readfds, NULL, NULL, NULL);

    if (ret == -1) {
        perror("select error");
    } else if (ret) {
        printf("select() indicates the file is ready for reading.\n");
        
        ssize_t bytes_read = read(fd, buffer, BUFFER_SIZE - 1);
        if (bytes_read >= 0) {
            printf("Read %zd bytes from the file.\n", bytes_read);
        } else {
            printf("read() error: %s\n", strerror(errno));
        }
    } else {
        printf("select() returned 0 (timeout). This shouldn't happen with no timeout set.\n");
    }

    close(fd);
    return 0;
}