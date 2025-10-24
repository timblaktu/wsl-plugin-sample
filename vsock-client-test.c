// Simple VSOCK client to test communication with NixOS-WSL systemd-shim
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/vm_sockets.h>
#include <errno.h>

#define PLUGIN_PORT 5001
#define VMADDR_CID_HOST 2  // Connect to host (Windows)

int main() {
    printf("VSOCK Client Test - Simulating WSL Plugin\n");
    printf("==========================================\n\n");
    
    // Create VSOCK socket
    int sock = socket(AF_VSOCK, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("Failed to create VSOCK socket");
        return 1;
    }
    
    // Set up connection to host on port 5001
    struct sockaddr_vm addr = {
        .svm_family = AF_VSOCK,
        .svm_port = PLUGIN_PORT,
        .svm_cid = VMADDR_CID_HOST,
    };
    
    printf("Attempting to connect to VSOCK host:5001...\n");
    
    // Connect to the host
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        printf("❌ Failed to connect: %s\n", strerror(errno));
        printf("   This is expected if no server is listening\n");
        close(sock);
        return 1;
    }
    
    printf("✅ Connected to VSOCK server!\n");
    
    // Receive configuration data
    char buffer[4096];
    ssize_t received = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (received <= 0) {
        printf("❌ Failed to receive data\n");
        close(sock);
        return 1;
    }
    
    buffer[received] = '\0';
    printf("\n📥 Received configuration (%zd bytes):\n", received);
    printf("---\n%s---\n\n", buffer);
    
    // Simulate processing the configuration
    printf("🔄 Processing configuration...\n");
    sleep(1);  // Simulate work
    
    // Send response
    const char* response = "STATUS ready\nMESSAGE All disks are ready";
    if (send(sock, response, strlen(response), 0) < 0) {
        printf("❌ Failed to send response\n");
        close(sock);
        return 1;
    }
    
    printf("✅ Sent response: %s\n", response);
    
    close(sock);
    printf("\n🎉 VSOCK communication test completed successfully!\n");
    return 0;
}